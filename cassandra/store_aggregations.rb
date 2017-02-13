require 'date'
require 'json'

require_relative './utilities'
include Utils

#
# Goal: to be able to quickly query up to 100,000 data points for charting data.
#

# in n-minute increments
RELOAD_DATA = ENV['RELOAD'] == 'true'
AGGREGATION_BUCKETS = [1, 5, 10, 30, 60, 120, 240, 360, 720, 1440]
DEFAULT_HOURS_AGGREGATION = {
  1    => 1,
  2    => 1,
  3    => 1,
  4    => 1,
  6    => 1,
  8    => 1,
  16   => 5,
  24   => 5,    # 1d
  48   => 10,   # 2
  168  => 30,   # 7
  336  => 60,   # 14
  720  => 120,  # 30
  1440 => 240,  # 60
  2160 => 360,  # 90
  4320 => 720,  # 180
  8760 => 1440  # 365
}

if RELOAD_DATA
  # generate schema
  dir = File.dirname(File.absolute_path(__FILE__))
  spath = File.join dir, 'aggregation_schema.cql'

  puts "run script at #{spath}"
  `cqlsh -f #{spath}`
end

def time_floor(time, offset_in_seconds)
  Time.at(time - (time.to_i % offset_in_seconds))
end

# Time is sliced into compatibly sized buckets, like so:
#   1: | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | |
#   5: |         |         |         |         |         |         |
#  10: |                   |                   |                   |
#  30: |                                                           |
#  60: | etc.
# 120: |
# 256: |
#
# Data is received continuously and data for the preceeding chunk is rolled up
# every (minute). For example:
#
#   * = rollup process runs
#   - = minutes batched
#
#                           *
#   1: |-|-|-|-|-|-|-|-|-|-| | | | | | | | | | | | | | | | | | | | |
#   5: |---------|---------|         |         |         |         |
#  10: |-------------------|                   |                   |
#  30: |                                                           |
#  60: | etc.
# 120: |
# 256: |
#
# Since the rollup job triggered in the middle of a 30 minute bucket, that data
# isn't aggregated yet. It will get picked up _after_ the 30 minute block has
# completed.
#
# Normally this work would be bundled up in a job / async worker and the `time`
# argument would be provided by the system clock. So, as long as the aggregate
# builder runs each minute, all buckets will remain filled
def update_aggregates(session, feed, time_step, time)
  batch = session.batch do |b|
    prev_span = nil
    AGGREGATION_BUCKETS.each do |span|
      span_in_seconds = span * 60

      # The end of the previous slice for this aggregation bucket. All buckets
      # are aligned on the start of Unix epoch time.
      slice_ending_at = time_floor(time, span_in_seconds)

      select = session.prepare %[select val from data_aggregate_#{span} where fid=? and slice=?]
      existing = session.execute(select, arguments: [feed, slice_ending_at])

      # if no roll-up has been calculated, do it now
      if existing.rows.size === 0
        args = {
          fid: feed,
          # a slice is a collection of data points up to the end time
          slice: slice_ending_at,
          # Store at most 1000 data points for the given time span.
          # Alternatively, we could set TTL to the same as the Feed storage
          # length (7 day, 1 year, etc.) if we want to support ranged queries.
          ttl: 1000 * span
        }

        # the beginning of the previous slice
        slice_start = slice_ending_at - span_in_seconds

        if prev_span
          # gather from previous aggregation
          gather = session.prepare %[select val, loc, val_count, sum, max, min, avg
                                     from data_aggregate_#{prev_span}
                                     where fid = :fid AND slice >= :slice_start AND slice <= :slice_end]

          results = session.execute(gather, arguments: {fid: feed, slice_start: slice_start, slice_end: slice_ending_at})

          r_count = results.rows.size
          prev_span = span
          next if r_count === 0

          last_val = nil
          last_loc = nil

          # calculate
          sum = 0
          count = 0
          max = -Float::INFINITY
          min = Float::INFINITY

          results.rows.each do |row|
            sum += row['sum']
            count += row['val_count']
            min = min < row['min'] ? min : row['min']
            max = max > row['max'] ? max : row['max']
            last_val = row['val']
            last_loc = row['loc']
          end
          avg = sum / count

        else
          # select all data received in the slice
          gather = session.prepare %[select val, loc from data where fid = :fid AND id > minTimeuuid(:slice_start) AND id < maxTimeuuid(:slice_end)]
          results = session.execute(gather, arguments: {fid: feed, slice_start: slice_start, slice_end: slice_ending_at})

          r_count = results.rows.size
          prev_span = span
          next if r_count === 0

          last_val = nil
          last_loc = nil
          sum = 0
          count = 0
          max = -Float::INFINITY
          min = Float::INFINITY

          results.rows.each do |row|
            sum += row['val']
            count += 1
            min = min < row['val'] ? min : row['val']
            max = max > row['val'] ? max : row['val']
            last_val = row['val']
            last_loc = row['loc']
          end
          avg = sum / (count * 1.0)
        end

        args[:val] = last_val
        args[:loc] = last_loc
        args[:sum] = sum
        args[:avg] = avg
        args[:val_count] = count
        args[:min] = min
        args[:max] = max

        puts "  INSERT FOR %4im AGGREGATION FROM %s TO %s" % [span, slice_start, slice_ending_at]
        insert = session.prepare %[INSERT INTO data_aggregate_#{span} (fid, val, loc, val_count, sum, min, max, avg, slice)
                                   VALUES (:fid, :val, :loc, :val_count, :sum, :min, :max, :avg, :slice) USING TTL :ttl]
        b.add insert, arguments: args
      end
    end
  end

  return 0 if batch.statements.size === 0

  session.execute batch, consistency: :all

  return batch.statements.size
end

# returns Time value from just before start of data
def batch_insert_data(session, start_time)
  gen = Cassandra::Uuid::Generator.new
  stmt = session.prepare %[INSERT INTO data (id, fid, val, loc, ctime) VALUES (?, ?, ?, ?, ?)]

  time_step = 30 # seconds
  points = 1000
  value = 50.0
  loc = [-40.000, 40.000, 100.0]

  curr_time = start_time - (time_step * points)

  start = Time.now
  puts "inserting #{points} records, one every #{time_step}s"

  # INSERT test data over a 3 day period, 30-second throttle
  batch = session.batch do |b|
    points.times do |n|
      # random walk
      value = value + (rand() * 4) - 2
      loc   = loc.map {|v| v + (rand() * 0.01) - 0.05}

      gen = Cassandra::Uuid::Generator.new

      b.add stmt, arguments: [gen.at(curr_time), 1, value, Cassandra::Tuple.new(*loc), curr_time]

      # simulate the passage of time
      curr_time = curr_time + time_step
    end
  end
  session.execute batch, consistency: :all

  return curr_time - 1
end

def get_charting_data(session, feed, chart_hours)
  aggregation_bucket = DEFAULT_HOURS_AGGREGATION[chart_hours]
  limit = (chart_hours * 60) / aggregation_bucket
  puts "  getting #{ limit} records"

  query = session.prepare "SELECT avg as val, slice as ctime FROM data_aggregate_#{ aggregation_bucket } LIMIT #{ limit }"
  session.execute(query)
end

def get_mapping_data(session, feed, chart_hours)
  aggregation_bucket = DEFAULT_HOURS_AGGREGATION[chart_hours]
  limit = (chart_hours * 60) / aggregation_bucket
  puts "  getting #{ limit} records"

  query = session.prepare "SELECT val, loc, slice as ctime FROM data_aggregate_#{ aggregation_bucket } LIMIT #{ limit }"
  result = session.execute(query)
end

# given a data point uuid, update the raw data and aggregations tables
# def delete_data_point(session, uuid)
# end
# def update_data_point(session, uuid, value)
# end

def timed message
  start = Time.now
  puts message
  yield
  puts "in %.2fms\n\n" % [(Time.now - start) * 1000.0]
end
session = connect!

if RELOAD_DATA
  timed "INSERT BATCH DATA" do
    batch_insert_data(session, Time.now)
  end
end

res = session.execute "SELECT id FROM data WHERE fid = 1 ORDER BY id ASC LIMIT 1"
earliest = res.rows.first['id'].to_time

puts
puts "DATA STARTS AT #{earliest}"
puts

# ---------------

if RELOAD_DATA
  timed "UPDATE AGGREGATES" do
    update_count = 0
    curr_time = earliest + 5 # make sure we're offset from data points insert times
    while curr_time < (Time.now + 60)
      timed "aggregator runs at #{ curr_time }" do
        update_count += update_aggregates(session, 1, 30, curr_time)
      end

      # simulate the passage of time
      curr_time = curr_time + 60
    end
  end
end

def show_results(results)
  return if results.rows.size === 0

  col_names = []
  rowfmt = "%30s%30s%60s"

  puts rowfmt % ['ctime', 'val', 'loc']
  puts("-" * 120)
  results.rows.each do |row|
    puts rowfmt % [row['ctime'], row['val'], row['loc']]
  end
  puts
  puts
end

def to_json(results)
  return JSON.generate({columns: [], data: []}) if results.rows.size === 0
  cols = results.rows.first.keys
  data = {
    columns: cols,
    data: results.rows.map {|row|
      cols.map {|c| row[c]}
    }
  }
  JSON.generate(data)
end

valid_chart_hours = DEFAULT_HOURS_AGGREGATION.keys.sort

[1, 4, 8, 24, 168, 720, 4320, 8760].each do |len|
  timed "GET #{len}h CHART" do
    data = get_charting_data session, 1, len
    js = to_json(data)
    puts "  #{ js.slice(0, 90) }..."
    puts "  #{ js.size } bytes"
  end
end

#timed "GET h MAP" do
#  data = get_mapping_data session, 1, 720
#  # show_results(data)
#end
