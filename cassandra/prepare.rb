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

## MAPPED TABLE SCHEMA
#
# map_data_create = %[
# CREATE TABLE IF NOT EXISTS iotest.mapped_data_by_timeuuid (
#   fid int,
#   date timestamp,
#   values map<timeuuid, text>,
#   PRIMARY KEY ((uid, fid), id)
# ) WITH CLUSTERING ORDER BY (id DESC);
# ]
# execute_statement session, 'create mapped table', map_data_create
#
