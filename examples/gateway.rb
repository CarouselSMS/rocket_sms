require 'rubygems'
require 'redis'
require 'json'
require Dir.getwd + "/lib/rocket_sms"

RocketSMS.configure do |config|
  # config.redis_url = REDIS_URL
  config.configurations = 'examples/gateway.yml'
  config.log = Dir.getwd + '/tmp/gateway.log'
end

RocketSMS.start
