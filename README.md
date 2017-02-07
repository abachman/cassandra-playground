### Requirements

By default, a Cassandra server running at hostname `cassandra`, though you can update `cassandra/utilities.rb` to change that.

### Usage

```sh
$ bundle install
$ bundle exec ruby cassandra/prepare.rb
$ INSERT=true bundle exec ruby cassandra/original_table.rb
$ INSERT=true bundle exec ruby cassandra/simple_table.rb
```

Subsequent runs of the test scripts don't require the `INSERT=true` environment variable to be set.

## Results

On my machine, virtually no difference between "original" and "simple"

From `cassandra/original_table`:

```
selecting 100 times limit 1000
SELECTED 1000 RECORDS IN 2.281786 seconds
RESULT:
  AVERAGE SIZE = 1000.0
  AVERAGE TIME = 0.022801290000000002

selecting 50 times no limit
SELECTED RECORDS IN 11.329892 seconds
RESULT:
  AVERAGE SIZE = 10000.0
  AVERAGE TIME = 0.22656564000000004

counting 50 times
SELECTED RECORDS IN 0.451777 seconds
RESULT:
  AVERAGE SIZE = 2500.98
  AVERAGE TIME = 0.0089815

FOUND 49999 RECORDS IN 1.456699 SECONDS WITH 4723464 BYTES
```

From `cassandra/simple_table`:

```
selecting 100 times, limit 1000
SELECTED 1000 RECORDS IN 2.272761 seconds
RESULT:
  AVERAGE SIZE = 1000.0
  AVERAGE TIME = 0.022708889999999992

selecting 50 times, no limit
SELECTED RECORDS IN 10.90465 seconds
RESULT:
  AVERAGE SIZE = 10000.0
  AVERAGE TIME = 0.21805681999999993

counting 50 times
SELECTED RECORDS IN 0.334528 seconds
RESULT:
  AVERAGE SIZE = 2499.22
  AVERAGE TIME = 0.006652340000000002

FOUND 49999 RECORDS IN 1.27551 SECONDS WITH 4729460 BYTES
```


## Conclusion

Gonna go fast when limiting queries to 1000 data points and sorting by `id`.
