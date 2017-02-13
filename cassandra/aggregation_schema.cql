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

-- aggregated data in 1 minute increments
CREATE TABLE data_aggregate_1 (
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


-- aggregated data in 5 minute increments
CREATE TABLE data_aggregate_5 (
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


-- aggregated data in 10 minute increments
CREATE TABLE data_aggregate_10 (
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


-- aggregated data in 30 minute increments
CREATE TABLE data_aggregate_30 (
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


-- aggregated data in 60 minute increments
CREATE TABLE data_aggregate_60 (
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


-- aggregated data in 120 minute increments
CREATE TABLE data_aggregate_120 (
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


-- aggregated data in 240 minute increments
CREATE TABLE data_aggregate_240 (
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


-- aggregated data in 360 minute increments
CREATE TABLE data_aggregate_360 (
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


-- aggregated data in 720 minute increments
CREATE TABLE data_aggregate_720 (
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


-- aggregated data in 1440 minute increments
CREATE TABLE data_aggregate_1440 (
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

