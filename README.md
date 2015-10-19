Promise Tracker Aggregator
------------
Basic Sinatra and MongoDB API for aggregating information collected using the [Promise Tracker Campaign Builder](https://github.com/c4fcm/Promise-Tracker-Aggregator) and [Promise Tracker Mobile Client](https://github.com/c4fcm/Promise-Tracker-Mobile).

To Set Up
------------

1. Create a config.yml file based on template. This file should contain the private keys used by the Promise Tracker Builder and Mobile Client in order to post data.
2. Run `bundle install`


To Run
----------

Run `rackup config.ru`


Deploying to Production
-----------------------

1. Make sure to `sudo chown -R www-data:www-data public/` so the web user can save images