module RocketSMS

  class Transceiver

    def initialize(id, redis_url, log_location)
      @id, @redis_url, @log_location = id, redis_url, log_location
      @active = true
      @online = false
    end

    def redis
      @redis ||= EM::Hiredis.connect(@redis_url)
    end

    def logger
      Logger.new(@log_location)
    end

    def queues
      RocketSMS.queues
    end

    def throughput
      @settings && @settings[:throughput] || 1.0
    end

    def start
      EM.threadpool_size = 32
      EM.run do
        # Set quantum to 10 milliseconds to support throughputs up to 100 MTs/sec
        EM.set_quantum(10)
        logger.info "Starting Transceiver #{@id}"
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
        logger.info "#{@id} - Forcing Exit. Check your data for losses."
        shutdown
      else
        logger.info "#{@id} - Stopping. Waiting 5 seconds for pending operations to finish."
        @kill = true
        @active = false
        @connection.close_connection_after_writing if @connection
        @dispatcher.cancel if @dispatcher
        @configurator.cancel if @configurator
        @reconnector.cancel if @reconnector
        EM::Timer.new(5){ shutdown }
      end
    end

    def shutdown
      logger.info "#{@id} - Shutdown complete."
      EM.stop
    end

    def configure
      redis.get("gateway:transceivers:#{@id}:settings") do |payload|
        if payload
          @settings = MultiJson.load(payload, symbolize_keys: true)
        else
          stop
        end
      end
      @configurator = EM::Timer.new(1){ configure } if @active
    end

    def connect
      if @settings and @active
        logger.info "Connecting transceiver #{@id}."
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
      if @active
        interval = @online ? throughput**-1 : 1
        @dispatcher = EM::Timer.new(interval){ dispatch }
      end
      redis.rpop(queues[:mt][:dispatch]) do |payload|
        if payload
          now = Time.now.to_f
          message = Message.from_json(payload)
          if message.send_at > now
            logger.info "Message #{message.id} detected on #{@id} but still cannot be sent. Pushing to dispatch queue."
            redis.lpush(queues[:mt][:dispatch], payload)
          elsif message.send_at <= now and now < message.expires_at
            logger.info "Message #{message.id} detected on #{@id}. Sending."
            send_message(message)
          elsif message.expires_at <= now
            logger.info "Message #{message.id} detected on #{@id} but has expired. Retrying."
            message.add_pass
            redis.lpush(queues[:mt][:pending], message.to_json)
          end
        end
      end
    end

    def send_message(message)
      if @online
        logger.info "Sending Message #{message.id} through #{@id}."
        @connection.send_mt(message.id,message.sender,message.receiver,message.body)
      else
        logger.info "#{@id} is not connected. Pushing message #{message.id} to dispatch queue."
        redis.lpush(queues[:mt][:dispatch], message.to_json)
      end
    end


    def mo_received(transceiver, pdu)
      logger.info "#{@id} - Message Received"
      ticket = { pdu: { source_addr: pdu.source_addr, short_message: pdu.short_message, destination_addr: pdu.destination_addr } }
      EM.next_tick { redis.lpush(queues[:mo],MultiJson.dump(ticket)) }
    end
  
    def delivery_report_received(transceiver, pdu)
      logger.info "#{@id} - DR Received"
      ticket = { pdu: { source_addr: pdu.source_addr, short_message: pdu.short_message, destination_addr: pdu.destination_addr } }
      EM.next_tick { redis.lpush(queues[:dr],MultiJson.dump(ticket)) }
    end
  
    def message_accepted(transceiver, mt_message_id, pdu)
      logger.info "#{@id} - Message #{mt_message_id} - Accepted"
      ticket = { message_id: mt_message_id }
      EM.next_tick { redis.lpush(queues[:mt][:success],MultiJson.dump(ticket)) }
    end
  
    def message_rejected(transceiver, mt_message_id, pdu)
      logger.info "#{@id} - Message #{mt_message_id} - Rejected"
      ticket = { message_id: mt_message_id }
      EM.next_tick { redis.lpush(queues[:mt][:failure],MultiJson.dump(ticket)) }
    end
  
    def bound(transceiver)
      logger.info "#{@id} - Transceiver Bound"
      @online = true
      @reconnector = nil
    end
  
    def unbound(transceiver)  
      logger.info "#{@id} - Transceiver Unbound"
      if @active and !@reconnector
        logger.info "#{@id} is not connected. Retrying in 10 seconds."
        @reconnector = EM::Timer.new(10){ connect } unless @reconnector
      end
      @online = false
    end

  end

end
