require 'rocket_sms'

path = File.dirname(File.expand_path(__FILE__))

Process.daemon(true) if ARGV[0]
pid = Process.pid

FileUtils.mkdir_p "#{path}/tmp/pids"
FileUtils.mkdir_p "#{path}/logs"

IO.write("#{path}/tmp/pids/gateway.pid", pid)

environment = ARGV[0] || "development"

RocketSMS.configure do |config|
  config.settings = '#{path}/gateway.yml'
  config.log_location = "#{path}/logs/gateway.log"
end

RocketSMS.start