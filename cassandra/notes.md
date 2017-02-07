Based on http://datascale.io/cassandra-partitioning-and-clustering-keys-explained/

## Primary Keys

A single column Primary Key is also called a Partition Key.

When Cassandra is deciding where in the cluster to store this particular piece
of data, it will hash the partition key.  The value of that hash dictates where
the data will reside and which replicas will be responsible for it.

An example might look like this:

```cql
CREATE TABLE IF NOT EXISTS iotest.data_by_timeuuid (
  id timeuuid,
  uid int,
  fid int,
  val text,
  PRIMARY KEY (id)
);
```

## Compound Keys

A multi-column primary key is called a Compound Key.

An interesting characteristic of Compound Keys is that only the first column is
considered the Partition Key.  There rest of the columns in the Primary Key
clause are Clustering Keys.

## Clustering Keys

Each additional column that is added to the Primary Key clause is called a
Clustering Key.  A clustering key is responsible for sorting data within the
partition. By default, the clustering key columns are sorted in ascending order.

In this version, `id` is still the Partition Key, `fid` is a clustering key:

```cql
CREATE TABLE IF NOT EXISTS iotest.data_by_timeuuid (
  id timeuuid,
  uid int,
  fid int,
  val text,
  PRIMARY KEY (id, fid)
);
```

## Composite Key

A Composite Key is when you have a multi-column Partition Key.

This is what we're using on IO right now. `(uid, fid)` is the Partition Key,
`id` is a clustering key. Together `uid` and `fid` make up a Composite Partition [Primary] Key.

```cql
CREATE TABLE IF NOT EXISTS iotest.data_by_timeuuid (
  id timeuuid,
  uid int,
  fid int,
  val text,
  PRIMARY KEY ((uid, fid), id)
) WITH CLUSTERING ORDER BY (id DESC);
```

We could probably get away with dropping `uid` from the Partition Key and just
go with `((fid), id)` since the querying process will already have a valid feed
id (`fid`). User id is superfluous.

## Summary

* Primary Keys, also known as Partition Keys, are for locating your data to a partition in the cluster.
* Composite Keys are complex Partition Keys and are for including more columns in the calculation of the partition.
* Compound Keys are for including other columns in the filter but not affecting the partition.
* Clustering Keys are for sorting your data on the partition.



