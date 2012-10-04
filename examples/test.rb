# encoding: utf-8
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
  45.times do |i|
    msgs = []
    msgs << {id: "#{SecureRandom.hex(8)}", sender: dids.sample[:number], receiver: '9999999999', body: 'Attention LOs: Rob Huddle will be on vacation from Oct 4th - Oct 12th. In his absence, please contact Rachael Hawk with all urgent matters. Thank you' }
    body = %q{ @$¥èéùìòÇØøÅå_^{}\[~]|ÆæßÉ !"#¤%&(')*+,-./0123456789:;<=>? ¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"}
    msgs << {id: "#{SecureRandom.hex(8)}", sender: dids.sample[:number], receiver: '9999999999', body: body } 
    msgs.each do |m|
      score = Time.now.to_i
      r.zadd('gateway:queues:mt:pending', score, m.to_json)
    end
  end
end

threads = []
threads << Thread.new do
  while true do
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



