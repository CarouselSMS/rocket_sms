module RocketSMS

  class Transceiver

    def initialize(id, redis_url, log_location)
      @id, @redis_url, @log_location = id, redis_url, log_location
      @active = true
      @online = false
      @fast = false
      @settings = {}
    end

    def redis
      @redis ||= EM::Hiredis.connect(@redis_url)
    end

    def dredis
      @dredis ||= EM::Hiredis.connect(@redis_url)
    end

    def logger
      @logger ||= Logger.new(@log_location)
    end

    def log(msg, level = 'info')
      if EM.reactor_running?
        EM.defer{ logger.send(level, msg) }
      else
        logger.send(level, msg)
      end
    end

    def queues
      RocketSMS.queues
    end

    def throughput
      @settings && @settings[:throughput] ||= 1.0
    end

    def start
      EM.threadpool_size = 128
      EM.set_max_timers(100_000)
      EM.run do
        log "Starting Transceiver #{@id}"
        # Set quantum to 10 milliseconds to support throughputs up to 100 MTs/sec
        EM.set_quantum(10)
        # Detect transceiver configuration from Redis.
        configure
        # Connect
        connect
        # Start detecting and dispatching MTs
        dispatch
        # Trap exit-related signals
        Signal.trap("INT") { |signal| stop(signal) }
        Signal.trap("TERM") { |signal| stop(signal) }
      end
    end

    def stop(signal = nil)
      if @kill
        log "#{@id} - Forcing Exit. Check your data for losses."
        shutdown
      else
        log "#{@id} - Stopping. Waiting 5 seconds for pending operations to finish."
        @kill = true
        @active = false
        @connection.close_connection_after_writing if @connection
        @dispatcher.cancel if @dispatcher
        @configurator.cancel if @configurator
        @reconnector.cancel if @reconnector
        redis.del("gateways:transceivers:#{@id}")
        EM::Timer.new(5){ shutdown }
      end
    end

    def shutdown
      log "Transceiver #{@id} DOWN."
      EM.stop
    end

    def configure
      return unless @active
      @configurator = EM::Timer.new(1){ configure }
      redis.multi
      redis.hget("gateway:transceivers:#{@id}", "throughput")
      redis.hget("gateway:transceivers:#{@id}", "connection")
      redis.exec do |response|
        if response or response.flatten.empty?
          throughput_payload = response[0]
          connection_payload = response[1]
          @settings[:throughput] = throughput_payload.to_f
          @settings[:connection] = MultiJson.load(connection_payload, symbolize_keys: true)
        else
          stop
        end
      end
    end

    def connect
      return unless @active
      if @settings and @settings[:connection]
        log "Connecting transceiver #{@id}."
        @connection = EM.connect(
          @settings[:connection][:host], 
          @settings[:connection][:port], 
          Smpp::Transceiver, 
          @settings[:connection], 
          self
        )
      else
        EM::Timer.new(1){ connect }
      end
    end

    def dispatch
      return unless @active
      interval = @fast ? throughput**-1 : 0.5
      @dispatcher = EM::Timer.new(interval){ dispatch }
      redis.multi
      redis.zrange("gateway:transceivers:#{@id}:dispatch", 0, 0)
      redis.zremrangebyrank("gateway:transceivers:#{@id}:dispatch", 0, 0)
      redis.exec do |response|
        if response
          payload = response[0][0]
          if payload
            @fast = true
            now = Time.now.to_f
            message = Message.from_json(payload)
            if message.send_at > now
              log "Message #{message.id} detected on #{@id} but still cannot be sent. Pushing to dispatch queue."
              score = (message.send_at * 1000).to_i
              redis.zadd("gateway:transceivers:#{@id}:dispatch", score , payload)
            elsif message.send_at <= now and now < message.expires_at
              log "Message #{message.id} detected on #{@id}. Sending."
              send_message(message)
            elsif message.expires_at <= now
              log "Message #{message.id} detected on #{@id} but has expired. Retrying."
              message.add_pass
              redis.lpush(queues[:mt][:pending], message.to_json)
            end
          else
            @fast = false
          end
        end
      end
    end

    def register
      stat = @online ? 'online' : 'offline'
      redis.hset("gateway:transceivers:#{@id}", 'status', stat)
    end

    def send_message(message)
      if @online
        log "Sending Message #{message.id} through DID #{message.sender} via #{@id}."
        @connection.send_mt(message.id,message.sender,message.receiver,message.body)
      else
        log "#{@id} is not connected. Pushing message #{message.id} to dispatch queue."
        score = (message.send_at * 1000).to_i
        redis.zadd("gateway:transceivers:#{@id}:dispatch", score , payload)
      end
    end

    def mo_received(transceiver, pdu)
      log "#{@id} - Message Received"
      ticket = { pdu: { source_addr: pdu.source_addr, short_message: pdu.short_message, destination_addr: pdu.destination_addr } }
      EM.next_tick { redis.lpush(queues[:mo],MultiJson.dump(ticket)) }
    end
  
    def delivery_report_received(transceiver, pdu)
      log "#{@id} - DR Received"
      ticket = { pdu: { source_addr: pdu.source_addr, short_message: pdu.short_message, destination_addr: pdu.destination_addr } }
      EM.next_tick { redis.lpush(queues[:dr],MultiJson.dump(ticket)) }
    end
  
    def message_accepted(transceiver, mt_message_id, pdu)
      log "#{@id} - Message #{mt_message_id} - Accepted"
      ticket = { message_id: mt_message_id }
      EM.next_tick { redis.lpush(queues[:mt][:success],MultiJson.dump(ticket)) }
    end
  
    def message_rejected(transceiver, mt_message_id, pdu)
      log "#{@id} - Message #{mt_message_id} - Rejected"
      ticket = { message_id: mt_message_id }
      EM.next_tick { redis.lpush(queues[:mt][:failure],MultiJson.dump(ticket)) }
    end
  
    def bound(transceiver)
      log "#{@id} - Transceiver Bound"
      @online = true
      @reconnector = nil
      register
    end
  
    def unbound(transceiver)  
      log "#{@id} - Transceiver Unbound"
      if @active
        log "#{@id} is not connected. Retrying in 10 seconds."
        @reconnector.cancel if @reconnector
        @reconnector = EM::Timer.new(10){ connect }
      end
      @online = false
      register
    end

  end

end
