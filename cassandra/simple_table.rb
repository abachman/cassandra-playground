require_relative './utilities'
include Utils
session = connect!

execute_statement session, 'create nthCollector function', %[
  CREATE OR REPLACE FUNCTION nthCollector(state tuple<int, list<timeuuid>>, current timeuuid, nthval int)
  CALLED ON NULL INPUT
  RETURNS tuple<int, list<timeuuid>>
  LANGUAGE java
  AS $$
    state.setInt(0, state.getInt(0) + 1);

    if (state.getInt(0) % nthval == 0) {
      List<UUID> existing;
      if (state.getList(1, UUID.class) == null) {
        existing = new ArrayList<UUID>();
      } else {
        existing = state.getList(1, UUID.class);
      }
      existing.add(current);
      state.setList(1, existing);
    }

    return state;
  $$;
]

execute_statement session, 'create nthFinal function', %[
  CREATE OR REPLACE FUNCTION nthFinal(state tuple<int, list<timeuuid>>)
  CALLED ON NULL INPUT
  RETURNS list<timeuuid>
  LANGUAGE java
  AS $$
    return state.getList(1, UUID.class);
  $$;
]


execute_statement session, 'create nthRecord aggregate', %[
  CREATE OR REPLACE AGGREGATE nthRecord(timeuuid, int)
  SFUNC nthCollector
  STYPE tuple<int, list<timeuuid>>
  FINALFUNC nthFinal
  INITCOND (null, []);
]

DO_INSERT = ENV['INSERT'] == 'true'
TABLE_NAME = 'data_by_timeuuid_fid'
#
# CREATE TABLE IF NOT EXISTS iotest.data_by_timeuuid_fid (
#   id timeuuid,
#   fid int,
#   val text,
#   ctime timestamp,
#   mtime timestamp,
#   loc frozen <tuple <double, double, double>>,
#   PRIMARY KEY ((fid), id)
# ) WITH CLUSTERING ORDER BY (id DESC);
#

# add a lot of data points, 1 per second-ish

start = Time.now

user_id = 1
feed_id = 1
value = 50
batches = 50
per_batch = 1000
count = batches * per_batch
ttl = 2592000
curr_time = Time.now - count
earliest = curr_time
generator = Cassandra::Uuid::Generator.new
results = []

if DO_INSERT
  execute_statement session, "truncate #{TABLE_NAME}", %[TRUNCATE iotest.#{ TABLE_NAME }]
  puts "inserting #{ count } records into #{ TABLE_NAME }"
  original_insert = session.prepare "INSERT INTO #{ TABLE_NAME } (id, fid, val, ctime) VALUES (:id, :fid, :val, :ctime) USING TTL :ttl"

  batches.times do
    inner_start = Time.now
    batch = session.batch do |b|
      per_batch.times do
        timeuuid = generator.at(Time.at(curr_time))

        params = {
          id: timeuuid,
          fid: feed_id,
          val: value.to_s,
          ctime: Time.now,
          ttl: ttl
        }

        b.add(
          original_insert,
          arguments: params
        )

        # walk values
        curr_time += 1 + (((rand() * 2) - 1) / 10)
        value += (rand() * 2) - 1
      end
    end

    begin
      session.execute batch, consistency: :all, timeout: 10
      puts "  batch insert #{ per_batch } up to #{ curr_time } in #{ Time.now - inner_start }"
      sleep 0.5
    rescue Cassandra::Errors::WriteTimeoutError => ex
      puts "  (write timeout)"
      sleep 5
      retry
    end
  end

  puts "inserted #{count} records in #{ Time.now - start } seconds"
  puts "---"
  puts
else
  # find ealiest based on oldest record in DB
  res = session.execute "SELECT id FROM #{ TABLE_NAME } WHERE fid = #{ feed_id } ORDER BY id ASC LIMIT 1"
  earliest = res.rows.first['id'].to_time
end

count = session.execute("select count(1) from #{TABLE_NAME} where fid = 1;").rows.first['count']


nth = 100
puts "QUERY nth(#{ nth }) OF #{ count } RECORDS"
start = Time.now
results = session.execute "select nthRecord(id, #{nth}) as val_collection from #{TABLE_NAME} where fid = 1;"
# puts JSON.generate(results.rows.first)
puts "GOT #{results.rows.first['val_collection'].size} IN #{ Time.now - start}"

#### Running limit 1000 queries

# start = Time.now
# scount = 100
# limit  = 1000
# curr_time = earliest
# puts "selecting #{scount} times, limit #{limit}"
#
# statement = session.prepare "SELECT id, val, ctime FROM #{ TABLE_NAME }
#                              WHERE fid = ? AND id > ?
#                              LIMIT ?"
# results = []
# scount.times do
#   inner_start = Time.now
#
#   params = [
#     feed_id,
#     generator.at(Time.at(curr_time)),
#     limit
#   ]
#
#   results << [
#     session.execute(statement, arguments: params).size, # result size
#     Time.now - inner_start,                             # result timing
#   ]
#
#   # walk forwards
#   curr_time += 1
# end
#
# puts "SELECTED #{limit} RECORDS IN #{ Time.now - start } seconds"
# puts "RESULT:"
# puts "  AVERAGE SIZE = #{ results.inject(0) {|m, o| m += o[0]} / (scount * 1.0)}"
# puts "  AVERAGE TIME = #{ results.inject(0) {|m, o| m += o[1]} / (scount * 1.0)}"
# puts
#
# #### Running unlimited queries
#
# start = Time.now
# scount = 50
# curr_time = earliest
# puts "selecting #{scount} times, no limit"
#
# statement = session.prepare "SELECT id, val, ctime FROM  #{ TABLE_NAME }
#                              WHERE fid = ? AND id > ?"
# results = []
# scount.times do
#   inner_start = Time.now
#
#   params = [
#     feed_id,
#     generator.at(Time.at(curr_time))
#   ]
#
#   results << [
#     session.execute(statement, arguments: params).size, # result size
#     Time.now - inner_start,                             # result timing
#   ]
#
#   # walk forwards
#   curr_time += 1
# end
#
# puts "SELECTED RECORDS IN #{ Time.now - start } seconds"
# puts "RESULT:"
# puts "  AVERAGE SIZE = #{ results.inject(0) {|m, o| m += o[0]} / (scount * 1.0)}"
# puts "  AVERAGE TIME = #{ results.inject(0) {|m, o| m += o[1]} / (scount * 1.0)}"
# puts
#
# #### Running count queries
#
# start = Time.now
# ccount = 100
# curr_time = earliest
# puts "counting #{scount} times"
#
# statement = session.prepare "SELECT count(*) FROM  #{ TABLE_NAME }
#                              WHERE fid = ? AND id > ? AND id < ?"
# results = []
# scount.times do
#   inner_start = Time.now
#
#   params = [
#     feed_id,
#     generator.at(Time.at(curr_time)),
#     generator.at(Time.at(curr_time + 2500))
#   ]
#
#   results << [
#     session.execute(statement, arguments: params).rows.first['count'], # result
#     Time.now - inner_start,                             # result timing
#   ]
#
#   # walk forwards
#   curr_time += 1
# end
#
# puts "SELECTED RECORDS IN #{ Time.now - start } seconds"
# puts "RESULT:"
# puts "  AVERAGE SIZE = #{ results.inject(0) {|m, o| m += o[0]} / (scount * 1.0)}"
# puts "  AVERAGE TIME = #{ results.inject(0) {|m, o| m += o[1]} / (scount * 1.0)}"
# puts
#
# #### Paging through all records, building JSON
#
# require 'json'
#
# start = Time.now
# ccount = 100
# curr_time = earliest
# statement = session.prepare "SELECT id, ctime, val, loc FROM #{TABLE_NAME} WHERE fid = ? AND id > ?"
#
# results = session.execute statement, arguments: [feed_id, generator.at(Time.at(curr_time))]
# full_results = []
# loop do
#   results.rows.each do |row|
#     full_results << [
#       row['id'],
#       row['ctime'],
#       row['val'],
#       row['loc']
#     ]
#   end
#   break if results.last_page?
#   results = results.next_page
# end
#
# puts "FOUND #{full_results.size} RECORDS IN #{ Time.now - start } SECONDS WITH #{ JSON.generate(full_results).size } BYTES"

