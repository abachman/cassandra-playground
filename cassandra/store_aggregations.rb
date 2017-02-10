require 'date'
require 'json'

require_relative './utilities'
include Utils

#
# Goal: to be able to quickly query up to 100,000 data points for charting data.
#

session = connect!

execute_statement session, 'drop table', %[DROP TABLE IF EXISTS test_data]
execute_statement session, 'create table', %[
  CREATE TABLE test_data (
    id timeuuid,
    fid int,
    val double,
    ctime timestamp,
    PRIMARY KEY ((fid), id)
  ) WITH CLUSTERING ORDER BY(id DESC);
]


execute_statement session, 'drop table', %[DROP TABLE IF EXISTS test_data_updated]
execute_statement session, 'create table', %[
  CREATE TABLE test_data_updated (
    minute timestamp,
    fid int,
    PRIMARY KEY ((minute), fid)
  );
]


execute_statement session, 'drop agg table', %[DROP TABLE IF EXISTS test_data_aggregations]
execute_statement session, 'create agg table', %[
  CREATE TABLE test_data_aggregations (
    fid int,
    aggregate int,
    val double,
    slice timestamp,
    PRIMARY KEY ((fid, aggregate), slice)
  ) WITH CLUSTERING ORDER BY(slice desc);
]


def time_floor(time, offset)
  Time.at(time - (time.to_i % offset))
end

# Time is sliced like this:
#   2: |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
#   4: |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |
#   8: |           |           |           |           |           |           |           |           |
#  16: |                       |                       |                       |                       |
#  32: |                                               |                                               |
#  64: |                                                                                               |
# 127: | etc.
# 256: |
#
# Data is received continuously and data for the preceeding chunk is rolled up
# every (minute). For example:
#
#   * = rollup process runs
#   - = minutes batched
#
#                   *
#   2: |--|--|--|--|  |  |  |  | ...
#   4: |-- --|-- --|     |     |
#   8: |-- -- -- --|           |
#  16: |                       |
#
# Since the rollup job triggered in the middle of a 16 minute block, it is not
# rolled up. It will get picked up _after_ the 16 minute block has completed.
def update_aggregates(session, feed, time_step, time)

  puts "UPDATE AGGREGATES AT #{ time }"

  # check if exists
  select = session.prepare %[select val from test_data_aggregations where fid=? and aggregate=? and slice=?]
  # create
  insert = session.prepare %[INSERT INTO test_data_aggregations (fid, aggregate, val, slice) VALUES (:fid, :agg, :val, :slice) USING TTL :ttl]
  # accumulate
  gather = session.prepare %[select val from test_data where fid = :fid AND id > minTimeuuid(:start_time) AND id < maxTimeuuid(:end_time)]

  batch = session.batch do |b|
    [2, 4, 8, 16, 32, 64, 128, 256].each do |agg_factor|
      span = time_step * agg_factor

      # the end of the previous slice
      slice_ending_at = time_floor(time, span)

      existing = session.execute(select, arguments: [feed, agg_factor, slice_ending_at])

      # if no roll-up has been calculated, do it now
      if existing.rows.size === 0
        args = {
          fid: feed,
          agg: agg_factor,  # how many data points are being aggregated?
          slice: slice_ending_at, # a slice is a collection of data points up to the end time
          ttl: 1000 * span  # store at most 1000 data points for the given time span
        }

        # the beginning of the previous slice
        slice_start = slice_ending_at - span

        # select all data received in the slice
        results = session.execute(gather, arguments: {fid: feed, start_time: slice_start, end_time: slice_ending_at})
        r_count = results.rows.size
        next if r_count === 0

        sum = results.rows.map {|r| r['val']}.inject(0) {|memo, obj| memo + obj}
        avg = sum / (r_count * 1.0)

        args[:val] = avg

        puts "  INSERT FOR FACTOR %3im%20.4f UP TO %s" % [agg_factor / 2, avg, slice_ending_at]
        b.add insert, arguments: args
      end
    end
  end

  return if batch.statements.size === 0

  session.execute batch, consistency: :all
end


def insert_data(session, feed, time, value)
  gen = Cassandra::Uuid::Generator.new

  stmt = session.prepare %[INSERT INTO test_data (id, fid, val, ctime) VALUES (?, ?, ?, ?)]
  session.execute stmt, arguments: [gen.at(time), feed, value, time]

  # if we trigger an update on every insert, that causes excessive rewrites to existing accumulations
  # update_aggregates(session, feed, 30, time, value)
end

# get_charting_data "intelligently" selects an aggregation size that aims to
# get the given number of records over the given time range.
def get_charting_data(session, feed, start_time, end_time, requested_points)
  puts "CHART #{ feed } FROM #{ start_time } TO #{ end_time } GET #{ requested_points } POINTS"
  gen = Cassandra::Uuid::Generator.new

  start_id = gen.at(start_time)
  end_id = gen.at(end_time)

  # count available points in range
  counter = session.prepare %[SELECT count(*) from test_data WHERE fid = ? AND id >= ? AND id <= ?]
  count   = session.execute(counter, arguments: [feed, start_id, end_id]).rows.first['count']
  aggregate_by = nil

  # adjust aggregate factor as necessary
  if count > requested_points
    [2, 4, 8, 16, 32, 64, 128, 256].each do |agg|
      aggregate_by = agg
      break if (count / aggregate_by) <= requested_points
    end

    puts "  AGGREGATE BY FACTOR OF #{ aggregate_by }"
  else
    puts "  NO AGGREGATION FACTOR, COUNTED #{ count } REQUESTED #{ requested_points }"
  end

  # prepare default params
  params = {
    fid: feed
  }

  # query
  if aggregate_by
    query = session.prepare('select slice as ctime, val
                             from test_data_aggregations
                             where fid = :fid AND aggregate = :agg AND
                               slice >= :start_time AND slice <= :end_time')
    params[:agg] = aggregate_by
    params[:start_time] = time_floor(start_time, aggregate_by * 30) - 1
    params[:end_time] = end_time
  else
    query = session.prepare('select dateOf(id) as ctime, val from test_data
                             where fid = :fid AND id > minTimeuuid(:start_time) AND id < maxTimeuuid(:end_time)')
    params[:start_time] = start_time
    params[:end_time] = end_time

    puts "  PARAMS #{ params }"
  end

  result = session.execute(query, arguments: params)
end

def delete_data_point
end

def update_data_point
end

value = 50.0
curr_time = Time.now - 3000
earliest = curr_time - 1

start = Time.now
puts "inserting 1000 records, one every 10s"
1000.times do |n|
  insert_data session, 1, curr_time, value
  value = value + (rand() * 4) - 2
  # simulate the passage of time
  curr_time = curr_time + 10
end
puts "-- in #{ Time.now - start }"

end_time = curr_time
curr_time = earliest + 1 # offset a smidge

start = Time.now
puts "updating aggregates, once every 60s"

update_count = 0
while curr_time < end_time
  # def update_aggregates(session, feed, time_step, time)
  update_aggregates(session, 1, 30, curr_time)

  # simulate the passage of time
  curr_time = curr_time + 60
  update_count += 1
end
puts "-- #{ update_count } updates in #{ Time.now - start }"
puts

def show_results(results)
  col_names = []
  rowfmt = "%30s%30s"

  puts rowfmt % ['ctime', 'val']
  puts("-" * 60)
  results.rows.each do |row|
    puts rowfmt % [row['ctime'], row['val']]
  end
  puts
  puts
end

puts
puts "___________"
puts "-----------"
puts

collection = []
start = Time.now
50.times do
  inner_start = Time.now
  agg = [2, 4, 8, 16, 32, 64, 128, 256].sample
  res = session.execute "select slice as ctime, fid, val from test_data_aggregations where fid = 1 AND aggregate = #{agg}"
  collection << [
    res.size,
    Time.now - inner_start
  ]
end

puts "50 selects from test_data_aggregations in #{ Time.now - start }"
collection.each do |(sz, tm)|
  puts "  %8i%8.4f" % [sz, tm]
end

#
# a = get_charting_data session, 1, earliest, Time.now, 32
# b = get_charting_data session, 1, earliest, Time.now, 2
# c = get_charting_data session, 1, earliest, Time.now, 1000
# d = get_charting_data session, 1, earliest, Time.now, 300
# puts "A #{ a.rows.size }"
# show_results(a)
# puts "B #{ b.rows.size }"
# show_results(b)
# puts "C #{ c.rows.size }"
# show_results(c)
# puts "D #{ d.rows.size }"
# show_results(d)

