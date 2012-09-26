require 'rubygems'
require 'redis'
require 'json'
require Dir.getwd + "/lib/rocket_sms"

RocketSMS.configure do |config|
  config.settings = 'examples/gateway.yml'
end

RocketSMS.start
