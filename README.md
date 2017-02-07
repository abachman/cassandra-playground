### Requirements

By default, a Cassandra server running at hostname `cassandra`, though you can update `cassandra/utilities.rb` to change that.

### Usage

```sh
$ bundle install
$ bundle exec ruby cassandra/prepare.rb
$ bundle exec ruby cassandra/original_table.rb
$ bundle exec ruby cassandra/simple_table.rb
```
