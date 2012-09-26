require "#{ENV['ROCKET_SMS_PATH']}/lib/rocket_sms.rb"

id = ENV['TRANSCEIVER_ID'] || ARGV[0]
redis_url = ENV['REDIS_URL'] || ARGV[1]
log_location = ENV['LOG_LOCATION'] || ARGV[2]

transceiver = RocketSMS::Transceiver.new(id, redis_url, log_location)
transceiver.start
