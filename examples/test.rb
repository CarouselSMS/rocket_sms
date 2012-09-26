require 'rubygems'
require 'json'
require 'redis'
require 'securerandom'
r = Redis.new

r.del('gateway:queues:mt:pending')
r.del('gateway:queues:mt:retry')
r.del('gateway:queues:mt:dispatch')
r.del('gateway:queues:mt:success')
r.del('gateway:queues:mt:failure')

keys = r.keys('gateway:dids*')
keys.each{ |k| r.del(k) }
r.del('gateway:sets:dispatch')

dids = []
1000000000.upto(1000001000) do |num|
  did = { number: num, throughput: 1 }
  r.set("gateway:dids:#{num}", did.to_json )
  dids << did
end

t = Proc.new do
  50.times do |i|
    id = "#{SecureRandom.hex(8)}"
    message = {id: id, sender: dids.sample[:number], receiver: '9999999999', body: 'Hello World!' }
    r.lpush('gateway:queues:mt:pending', message.to_json)
  end
end

threads = []
threads << Thread.new do
  1000.times do
    t.call
    sleep 1
  end
end

threads << Thread.new do
  l = r.llen('gateway:queues:mt:success')
  while true do
    nl = r.llen('gateway:queues:mt:success')
    speed = l - nl
    puts speed
    l = nl
    sleep 1
  end
end

threads.each{ |t| t.join }



