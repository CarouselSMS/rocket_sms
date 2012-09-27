module RocketSMS

  class Scheduler
    include Singleton

    attr_accessor :redis_url, :log_location

    def initialize
      @redis_url, @log_location = nil, nil
      @active = true
      @fast = false
      @dids = {}
      @transceivers = {}
      @throughput = 0
    end

    def redis
      @redis ||= EM::Hiredis.connect(@redis_url)
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

    def start
      EM.threadpool_size = 128
      EM.set_max_timers(100_000)
      EM.run do
        log "Starting Scheduler"
        configure
        detect
        # Trap exit-related signals
        Signal.trap("INT") { |signal| stop(signal) }
        Signal.trap("TERM") { |signal| stop(signal) }
      end
    end

    def stop(signal = nil)
      if @kill
        log "Forcing Exit. Check your data for losses."
        shutdown
      else
        log "Stopping. Waiting 5 seconds for pending operations to finish."
        @kill = true
        @active = false
        EM::Timer.new(5){ shutdown }
      end
    end

    def shutdown
      log "Scheduler DOWN."
      EM.stop
    end

    def configure
      return unless @active
      @configurator = EM::Timer.new(1){ configure }
      redis.keys("gateway:transceivers:*") do |keys|
        if keys
          tids = keys.map{ |key| key.split(':')[2] }.uniq
          @transceivers.keys.each{ |k| @transceivers.delete(k) unless tids.include?(k) }
          tids.each do |tid|
            redis.hget("gateway:transceivers:#{tid}","status") do |resp|
              if resp == 'online'
                redis.hget("gateway:transceivers:#{tid}", "throughput") do |payload|
                  if payload
                    throughput = payload.to_f
                    log "Adding Transceiver #{tid}" if !@transceivers[tid]
                    @transceivers[tid] = throughput
                    set_throughput
                  elsif @transceivers[tid]
                    log "Removing Transceiver #{tid}" 
                    @transceivers.delete(tid)
                    set_throughput
                  end
                end
              else
                if @transceivers[tid]
                  log "Removing Transceiver #{tid}"
                  @transceivers.delete(tid)
                  set_throughput
                end
              end
            end
          end
        else
          @transceivers = {}
          @throughput = 0
        end
      end
    end

    def set_throughput
      @throughput = @transceivers.keys.map{ |tid| @transceivers[tid] }.reduce(&:+).to_f
    end

    def detect
      return unless @active
      interval = @fast ? 0.001 : 1
      @detector = EM::Timer.new(interval){ detect }
      redis.multi
      redis.zrange(queues[:mt][:pending], 0, 0, "WITHSCORES")
      redis.zremrangebyrank(queues[:mt][:pending], 0, 0)
      redis.exec do |response|
        if response
          (payload, score) = response[0]
          if payload and score
            @fast = true
            now = (Time.now.to_f*1000).to_i
            if score.to_i <= now
              process_payload(payload)
            else
              redis.zadd(queues[:mt][:pending], score, payload)
              @fast = false
            end
          else
            @fast = false
          end
        end
      end
    end

    def process_payload(msg_payload)
      message = Message.from_json(msg_payload)
      if message.pass > 5
        log "Message #{message.id} has exceeded maximum retries. Send it to Failed queue."
        redis.rpush(queues[:mt][:failure], message.to_json)
      else
        did_number = message.sender
        redis.get("gateway:dids:#{did_number}") do |payload|
          if payload
            log "Scheduling Message #{message.id} to be sent through DID #{did_number}"
            schedule(message, payload)
          else
            log "The DID #{did_number} for message #{message.id} is not configured. Retrying."
            retry_message(message)
          end
        end
      end
    end

    def schedule(message, did_payload)
      if @active
        if @transceivers.keys.empty? or @throughput == 0
          retry_message(message)
        else
          did = Did.from_json(did_payload)
          if !@dids[did.number]
            @dids[did.number] = {}
            @dids[did.number][:last_send] = Time.now.to_f + 1
          end
          interval = did.throughput.to_f**-1
          last_send = @dids[did.number][:last_send]
          if Time.now.to_f - last_send > interval
            base_time = Time.now.to_f + 1
          else
            base_time = last_send
          end
          message.send_at = base_time + interval
          message.expires_at = message.send_at + 50*interval
          @dids[did.number][:last_send] = message.send_at
          score = (message.send_at * 1000).to_i
          transceiver_id = pick_transceiver
          redis.zadd("gateway:transceivers:#{transceiver_id}:dispatch", score, message.to_json)
        end
      else
        score = (message.send_at * 1000).to_i
        redis.zadd(queues[:mt][:pending], score, message.to_json)
      end
    end

    def pick_transceiver
      tids = []
      @transceivers.each do |k,v|
        weight = (v.to_f/@throughput*100).to_i
        weight.times{ tids << k }
      end
      tids.flatten!
      tids.sample
    end

    def retry_message(message)
      if message.pass > 5
        log "Message #{message.id} has exceeded maximum retries. Send it to Failed queue."
        redis.rpush(queues[:mt][:failure], message.to_json)
      else
        message.add_pass
        score = (Time.now.to_f + 15)*1000.to_i
        redis.zadd(queues[:mt][:pending], score, message.to_json)
      end
    end

  end

end
