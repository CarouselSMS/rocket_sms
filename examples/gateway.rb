require 'rocket_sms'

RocketSMS.configure do |config|
  config.settings = 'examples/gateway.yml'
end

RocketSMS.start
