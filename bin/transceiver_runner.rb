#!/usr/bin/env ruby

require "rocket_sms"

id = ENV['TRANSCEIVER_ID'] || ARGV[0]
redis_url = ENV['REDIS_URL'] || ARGV[1]
log_location = ENV['LOG_LOCATION'] || ARGV[2] || STDOUT
log_level = ENV['LOG_LEVEL'] || Logger::INFO

transceiver = RocketSMS::Transceiver.new(id, redis_url, log_location, log_level)
transceiver.start
