#### Requirements

By default, a Cassandra server running at hostname `cassandra`, though you can update `cassandra/utilities.rb` to change that.

#### Usage

```sh
$ bundle install
$ bundle exec ruby cassandra/prepare.rb
$ RELOAD=true bundle exec ruby cassandra/store_aggregations.rb
```

Subsequent runs of the test script doesn't require the `RELOAD=true` environment variable to be set.
