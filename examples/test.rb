require 'rubygems'
require 'json'
require 'redis'
require 'securerandom'
r = Redis.new

10000000000.upto(10000000009) do |num|
  r.hset("gateway:dids:#{num}", 'throughput', 1 )
  r.hset("gateway:dids:#{num}", 'last_send', nil )
end

t = Proc.new do
  10.times do |i|
    id = "#{Time.now.to_f}-#{i}"
    message = {id: id, sender: '10000000000', receiver: '9999999999', body: 'Hello World!' }
    r.lpush('gateway:queues:mt:pending', message.to_json)
  end
  sleep(0.01)
end

t.call


