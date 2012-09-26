require "#{ENV['ROCKET_SMS_PATH']}/lib/rocket_sms.rb"

redis_url = ENV['REDIS_URL'] || ARGV[0]
log_location = ENV['LOG_LOCATION'] || ARGV[1]

scheduler = RocketSMS::Scheduler.instance
scheduler.redis_url = redis_url
scheduler.log_location = log_location
scheduler.start
