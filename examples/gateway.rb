require 'rubygems'
require 'redis'
require 'json'
require Dir.getwd + "/lib/lean_sms"

LeanSMS.configure do |config|
  # config.redis_url = REDIS_URL
  config.configurations = 'examples/gateway.yml'
  config.logger = Logger.new(Dir.getwd + '/tmp/gateway.log')
end

LeanSMS.start
