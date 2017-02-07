require_relative './utilities'
include Utils
session = connect!

DO_INSERT = ENV['INSERT'] == 'true'
TABLE_NAME = 'data_by_timeuuid'
#
# CREATE TABLE IF NOT EXISTS iotest.data_by_timeuuid (
#   id timeuuid,
# -- uid int,
#   fid int,
# -- gid int,
#   val text,
#   ctime timestamp,
#   mtime timestamp,
#   loc frozen <tuple <double, double, double>>,
#   PRIMARY KEY ((uid, fid), id)
# ) WITH CLUSTERING ORDER BY (id DESC);
#

# add 1000 data points, 1 per second-ish

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
  execute_statement session, 'truncate original table', %[TRUNCATE iotest.#{ TABLE_NAME }]
  puts "inserting #{ count } records into #{ TABLE_NAME }"
  original_insert = session.prepare 'INSERT INTO data_by_timeuuid (id, uid, fid, val, ctime) VALUES (:id, :uid, :fid, :val, :ctime) USING TTL :ttl'

  batches.times do
    inner_start = Time.now
    batch = session.batch do |b|
      per_batch.times do
        timeuuid = generator.at(Time.at(curr_time))

        params = {
          id: timeuuid,
          uid: user_id,
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
else
  # find ealiest based on oldest record in DB
  res = session.execute "SELECT id FROM #{ TABLE_NAME } WHERE uid = #{ user_id } AND fid = #{ feed_id } ORDER BY id ASC LIMIT 1"
  earliest = res.rows.first['id'].to_time
end

puts "inserted #{count} records in #{ Time.now - start } seconds"
puts "---"
puts


start = Time.now
scount = 100
limit  = 1000
curr_time = earliest
puts "selecting #{scount} times limit #{limit}"

statement = session.prepare "SELECT id, val, ctime FROM #{TABLE_NAME}
                             WHERE uid = ? AND fid = ? AND id > ?
                             LIMIT ?"
results = []
scount.times do
  inner_start = Time.now

  params = [
    feed_id,
    user_id,
    generator.at(Time.at(curr_time)),
    limit
  ]

  results << [
    session.execute(statement, arguments: params).size, # result size
    Time.now - inner_start,                             # result timing
  ]

  # walk forwards
  curr_time += 1
end

puts "SELECTED #{limit} RECORDS IN #{ Time.now - start } seconds"
puts "RESULT:"
puts "  AVERAGE SIZE = #{ results.inject(0) {|m, o| m += o[0]} / (scount * 1.0)}"
puts "  AVERAGE TIME = #{ results.inject(0) {|m, o| m += o[1]} / (scount * 1.0)}"
puts

#### Running unlimited queries

start = Time.now
scount = 50
curr_time = earliest
puts "selecting #{scount} times no limit"

statement = session.prepare 'SELECT id, val, ctime FROM data_by_timeuuid
                             WHERE uid = ? AND fid = ? AND id > ?'
results = []
scount.times do
  inner_start = Time.now

  params = [
    feed_id,
    user_id,
    generator.at(Time.at(curr_time))
  ]

  results << [
    session.execute(statement, arguments: params).size, # result size
    Time.now - inner_start,                             # result timing
  ]

  # walk forwards
  curr_time += 1
end

puts "SELECTED RECORDS IN #{ Time.now - start } seconds"
puts "RESULT:"
puts "  AVERAGE SIZE = #{ results.inject(0) {|m, o| m += o[0]} / (scount * 1.0)}"
puts "  AVERAGE TIME = #{ results.inject(0) {|m, o| m += o[1]} / (scount * 1.0)}"
puts


#### Running count queries

start = Time.now
ccount = 100
curr_time = earliest
puts "counting #{scount} times"

statement = session.prepare "SELECT count(*) FROM  #{ TABLE_NAME }
                             WHERE uid = ? AND fid = ? AND id > ? AND id < ?"
results = []
scount.times do
  inner_start = Time.now

  params = [
    user_id,
    feed_id,
    generator.at(Time.at(curr_time)),
    generator.at(Time.at(curr_time + 2500))
  ]

  results << [
    session.execute(statement, arguments: params).rows.first['count'], # result
    Time.now - inner_start,                             # result timing
  ]

  # walk forwards
  curr_time += 1
end

puts "SELECTED RECORDS IN #{ Time.now - start } seconds"
puts "RESULT:"
puts "  AVERAGE SIZE = #{ results.inject(0) {|m, o| m += o[0]} / (scount * 1.0)}"
puts "  AVERAGE TIME = #{ results.inject(0) {|m, o| m += o[1]} / (scount * 1.0)}"
puts

#### Paging through all records, building JSON

require 'json'

start = Time.now
ccount = 100
curr_time = earliest
statement = session.prepare "SELECT id, ctime, val, loc FROM #{TABLE_NAME} WHERE uid = ? AND fid = ? AND id > ?"

results = session.execute statement, arguments: [user_id, feed_id, generator.at(Time.at(curr_time))]
full_results = []
loop do
  results.rows.each do |row|
    full_results << [
      row['id'],
      row['ctime'],
      row['val'],
      row['loc']
    ]
  end
  break if results.last_page?
  results = results.next_page
end

puts "FOUND #{full_results.size} RECORDS IN #{ Time.now - start } SECONDS WITH #{ JSON.generate(full_results).size } BYTES"



