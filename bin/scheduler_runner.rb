#!/usr/bin/env ruby

require "rocket_sms"

redis_url = ENV['REDIS_URL'] || ARGV[0]
log_location = ENV['LOG_LOCATION'] || ARGV[1] || STDOUT

scheduler = RocketSMS::Scheduler.instance
scheduler.redis_url = redis_url
scheduler.log_location = log_location
scheduler.start
