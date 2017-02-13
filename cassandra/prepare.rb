require_relative './utilities'
include Utils
session = connect!

# testing keyspace
keyspace_create = %[ CREATE KEYSPACE IF NOT EXISTS iotest WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'}  AND durable_writes = true; ]
execute_statement session, 'create keyspace', keyspace_create

if ENV['REBUILD'] == 'true'
  execute_statement session, 'drop table', %[DROP TABLE iotest.data_by_timeuuid]
  execute_statement session, 'drop table', %[DROP TABLE iotest.data_by_timeuuid_fid]
end

## EXISTING TABLE SCHEMA

original_data_create = %[
CREATE TABLE IF NOT EXISTS iotest.data_by_timeuuid (
  id timeuuid,
  uid int,
  fid int,
  gid int,
  val text,
  ctime timestamp,
  mtime timestamp,
  loc frozen <tuple <double, double, double>>,
  PRIMARY KEY ((uid, fid), id)
) WITH CLUSTERING ORDER BY (id DESC);
]
execute_statement session, 'create original table', original_data_create

original_index = %[ CREATE INDEX IF NOT EXISTS data_by_timeuuid_on_gid ON data_by_timeuuid (gid); ]
execute_statement session, 'create original index', original_index

## SIMPLER KEY TABLE SCHEMA
table_create = %[
CREATE TABLE IF NOT EXISTS iotest.data_by_timeuuid_fid (
  id timeuuid,
  fid int,
  val text,
  ctime timestamp,
  mtime timestamp,
  loc frozen <tuple <double, double, double>>,
  PRIMARY KEY ((fid), id)
) WITH CLUSTERING ORDER BY (id DESC);
]
execute_statement session, 'create (fid) table', table_create

## AGGREGATE TABLE SCHEMA with range indexes
table_create = %[
CREATE TABLE IF NOT EXISTS iotest.data_by_timeuuid_agg (
  id timeuuid,
  fid int,
  val text,
  val_num decimal,
  ctime timestamp,
  mtime timestamp,
  loc frozen <tuple <double, double, double>>,

  aggregation_2 timestamp,
  aggregation_4 timestamp,
  aggregation_8 timestamp,
  aggregation_64 timestamp,
  aggregation_128 timestamp,
  aggregation_256 timestamp,
  aggregation_512 timestamp,
  aggregation_768 timestamp,
  aggregation_1536 timestamp,
  aggregation_3072 timestamp,

  PRIMARY KEY ((fid), id)
) WITH CLUSTERING ORDER BY (id DESC);
]
execute_statement session, 'drop agg table', 'DROP TABLE IF EXISTS iotest.data_by_timeuuid_agg;'
execute_statement session, 'create (agg) table', table_create

execute_statement session, 'create index', %[ CREATE INDEX IF NOT EXISTS data_by_2 ON data_by_timeuuid_agg (aggregation_2); ]
execute_statement session, 'create index', %[ CREATE INDEX IF NOT EXISTS data_by_4 ON data_by_timeuuid_agg (aggregation_4); ]
execute_statement session, 'create index', %[ CREATE INDEX IF NOT EXISTS data_by_8 ON data_by_timeuuid_agg (aggregation_8); ]
execute_statement session, 'create index', %[ CREATE INDEX IF NOT EXISTS data_by_64 ON data_by_timeuuid_agg (aggregation_64); ]
execute_statement session, 'create index', %[ CREATE INDEX IF NOT EXISTS data_by_128 ON data_by_timeuuid_agg (aggregation_128); ]
execute_statement session, 'create index', %[ CREATE INDEX IF NOT EXISTS data_by_256 ON data_by_timeuuid_agg (aggregation_256); ]
execute_statement session, 'create index', %[ CREATE INDEX IF NOT EXISTS data_by_512 ON data_by_timeuuid_agg (aggregation_512); ]
execute_statement session, 'create index', %[ CREATE INDEX IF NOT EXISTS data_by_768 ON data_by_timeuuid_agg (aggregation_768); ]
execute_statement session, 'create index', %[ CREATE INDEX IF NOT EXISTS data_by_1536 ON data_by_timeuuid_agg (aggregation_1536); ]
execute_statement session, 'create index', %[ CREATE INDEX IF NOT EXISTS data_by_3072 ON data_by_timeuuid_agg (aggregation_3072); ]
