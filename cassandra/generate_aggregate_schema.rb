
header = <<EOS
DROP KEYSPACE IF EXISTS iotest;
CREATE KEYSPACE iotest WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 1 };
USE iotest;

CREATE TABLE data (
  id timeuuid,
  fid int,
  val double,
  ctime timestamp,
  loc frozen <tuple <double, double, double>>,
  PRIMARY KEY ((fid), id)
) WITH CLUSTERING ORDER BY(id DESC);
EOS

# standard aggregate table format
aggregate_template = <<EOS

-- aggregated data in %s minute increments
CREATE TABLE data_aggregate_%s (
  fid int,
  slice timestamp,
  val double,                                  -- first value
  loc frozen <tuple <double, double, double>>, -- first location
  val_count int,
  sum double,
  max double,
  min double,
  avg double,
  PRIMARY KEY ((fid), slice)
) WITH CLUSTERING ORDER BY(slice desc);

EOS

puts header
%w(1 5 10 30 60 120 240 360 720 1440).each do |aggregation|
  puts aggregate_template % [aggregation, aggregation]
end
