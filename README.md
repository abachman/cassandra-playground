#### Requirements

By default, a Cassandra server running at hostname `cassandra`, though you can update `cassandra/utilities.rb` to change that.

#### Usage

```sh
$ bundle install
$ bundle exec ruby cassandra/prepare.rb
$ INSERT=true bundle exec ruby cassandra/original_table.rb
$ INSERT=true bundle exec ruby cassandra/simple_table.rb
```

Subsequent runs of the test scripts don't require the `INSERT=true` environment variable to be set.

# Charting Requirements

First our proposed plan levels:

* Storage: 1 point per 5 minutes, 1 year history. 105120 points.
* Speed:   1 point per second, no history
* Combo:   1 point per 30 seconds, 30 days history. 86400 points.

So, we'll need to provide charts that cover up to 100,000k data points. If we aggregate in Ruby, that'll be 5+ second queries on io-rails and the data store. And obviously, we can't send multiple MB of JSON back to the browser.

In addition to potentially very large data sets, features we also want include:

- fast storage
- fast reporting
- long term reporting (can retrieve every data point)
- flexible primary value type (string or number)
- comprehensive reporting (filter in various ways over any range of time)
- fluidity of throttling rate
- smooth charting regardless of rate
- user can delete and update data points

Dashboard charts can load `hours` of history, where `hours` is any positive value. Feed and Group charts load day, week, month, year charts. The maximum, in-browser size our charts can reach without going fullscreen is around ~1200px. If we aim for at most 1 data point per 4px, that's around 300 points per chart.

If we use fixed chart lengths and aggregate data over fixed periods (e.g., 1m per aggregate data point), we can have all the data prepared before we ever receive a query.

Time ranges used by other systems:

Kibana (ranges)

    Last 15 minutes
    Last 30 minutes
    Last 1 hour
    Last 4 hours
    Last 12 hours
    Last 24 hours
    Last 7 days
    Last 30 days
    Last 60 days
    Last 90 days
    Last 6 months
    Last 1 year
    Last 2 years
    Last 5 years

Grafana (ranges)

    Last 5 minutes
    Last 15 minutes
    Last 30 minutes
    Last 1 hour
    Last 3 hours
    Last 6 hours
    Last 12 hours
    Last 24 hours
    Last 7 days
    Last 30 days
    Last 60 days
    Last 90 days
    Last 6 months
    Last 1 year
    Last 2 years
    Last 5 years

I propose we use:

    Live (last X data points, ongoing historical feed)

    Last...  | Aggregation Minutes | Data Points
    1 hour   |                   1 | 60
    2 hours  |                   1 | 120
    4 hours  |                   1 | 240
    8 hours  |                   1 | 480
    24 hours |                   5 | 288
    2 days   |                  10 | 288
    7 days   |                  30 | 336
    14 days  |                  60 | 336
    30 days  |                 120 | 360
    60 days  |                 240 | 360
    90 days  |                 360 | 360
    6 months |                 720 | 360
    1 year   |                1440 | 365

## Moving Parts

This part includes a few pieces, demonstrated in `cassandra/store_aggregations.rb`.

1. Fixed chart history sizes.
1. Aggregation over fixed time spans, "aggregation minutes" in the table above.
1. An example aggregation building worker.

Additional changes are required:

* **io-rails**
    * needs to query the aggregation tables based on the chart size and bucket size
    * propagate updated values to aggregate tables
    * propagate deleted values to aggregate tables
    * API for charting data, e.g., `/feeds/:id/data/chart`
    * API for mapping data, e.g., `/feeds/:id/data/mapping`
* **io-ui**
    * charts should use a select box to provide a list of fixed chart sizes

Optional features:

1. Provide a choice of bucket size during chart creation.

## COMPLICATIONS

Not just of this way of doing things but of our system in general...

### Delete and update

Deleting and updating historical data is a non-traditional feature for a high-performance time-series data store. We can do it, it's just tricky and slightly more complex. Most time-series optimized stores don't do it at all.

### Changeable feed types

Expiring data quickly is a problem when it comes to switching Feeds from 1-year to 1-month data storage. Changeable feed types is also a pattern that encourages reusing an existing feed for a new purpose. Presumably even renaming and deleting old data.

**PROPOSAL:** What if, instead of allowing users to change feed types, we required them to archive old feeds and create a new one? That is, what if the UX pattern changed from "change, update all attributes" to "archive, create". Archived feeds preserve data for their previously allotted time, new feeds always have a clean slate. *DELETING* an old feed, instead of archiving or in addition to archiving would also be allowed. Archived feeds could still be seen in feed lists, but can no longer be used on dashboards.

The only problem with this approach is that because of our use of non-unique keys in the API, we have to either add a suitably random tag to archived feed keys or allow the use of guaranteed unique IDs (`feed.id` instead of just `feed.key`) in the API to avoid collisions with new / active feed records.

### Multi-tenant time-series data storage

... is hard.

We're kind of on our own here. Everyone who can do this already is selling it, not writing open source software to help others do it. Similar to the delete & update problem, most time-series stores are for _your_ data, not everyone's data.

We might be able to change that, though, if producing some open-source is interesting to us.

## Benefit

Why go through all this trouble?

### Very fast reporting

Straight reading and generating simple JSON for ~500 data points on my machine takes less than 15ms. Any solution that involves rereading the data table will take 10 to 100x as long, no matter what data store we use unless it's building the specialized aggregate indexes for us.

### Arbitrary throttle rates

By detaching charting from the speed at which data accumulates, we can set throttles wherever we want them and still give people fast reports. In fact, my suspicion is that we could bump up our proposed paid data rates by 5 or 10x and still have smooth performance.

### Other kinds of aggregation

nth record queries on a rolling basis should be possible. Basically, anything that we want to come out in a chart we can write as an async, eventually consistent worker separate from the raw data insert.

# Updating IO Production

To make this change in production we'll need:

1. update cassandra schema to reflect the aggregate table structure
1. add worker process to perform aggregations
1. read from new data table for normal queries
1. read from charting (aggregate) tables for charts

