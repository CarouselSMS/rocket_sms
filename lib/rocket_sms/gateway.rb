module RocketSMS

  class Gateway
    include Singleton
    extend Forwardable

    def_delegators :RocketSMS, :settings, :redis, :logger, :redis_url, :log_location

    def initialize
      @scheduler = {}
      @transceivers = {}
      @path = Gem::Specification.find_by_name('rocket_sms').gem_dir
    end

    def log(msg, level = 'info')
      if EM.reactor_running?
        EM.defer{ logger.send(level, msg) }
      else
        logger.send(level, msg)
      end
    end

    def start
      EM.run do
        log "Starting Gateway"
        startup
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
        Process.kill('TERM', @scheduler[:pid])
        Process.wait(@scheduler[:pid]) if @scheduler[:pid]
        if @transceivers
          @transceivers.each_value{ |t| Process.kill('TERM', t[:pid]);  Process.wait(t[:pid]) if t[:pid] }
        end
        EM::Timer.new(5){ shutdown }
      end
    end

    def shutdown
      Process.kill('TERM', @scheduler[:pid])
      if @transceivers
        @transceivers.each_value{ |t| Process.kill('TERM', t[:pid]);  Process.wait(t[:pid]) if t[:pid] }
      end
      log "Gateway DOWN."
      EM.stop
    end

    def startup
      clean_up_stale_transceivers
    end

    def clean_up_stale_transceivers
      redis.keys("gateway:transceivers:*") do |keys|
        op = Proc.new do |key, iter|
          redis.del(key) do |resp|
            iter.next
          end
        end
        cb = Proc.new do |responses|
          setup_transceivers
        end
        EM::Iterator.new(keys).each(op,cb)
      end
    end

    def setup_transceivers
      # Clean up stale transceivers
      op = Proc.new do |tid, iter|
        tsettings = settings[:transceivers][tid]
        redis.multi
        redis.hset("gateway:transceivers:#{tid}", "throughput", tsettings[:throughput])
        redis.hset("gateway:transceivers:#{tid}", "connection", MultiJson.dump(tsettings[:connection]))
        redis.exec do |resp|
          iter.next
        end
      end
      cb = Proc.new do |responses|
        start_scheduler
        start_transceivers
      end
      EM::Iterator.new(settings[:transceivers].keys).each(op,cb)
    end

    def start_scheduler
      cmd = "bundle exec ruby #{@path}/bin/scheduler_runner.rb"
      @scheduler[:pid] = Process.spawn({ "REDIS_URL" => redis_url, "LOG_LOCATION" => (log_location == STDOUT ? nil : log_location) }, cmd)
    end

    def start_transceivers
      settings[:transceivers].each do |tid, settings|
        cmd = "bundle exec ruby #{@path}/bin/transceiver_runner.rb"
        @transceivers[tid] = {}
        @transceivers[tid][:pid] = Process.spawn({ "TRANSCEIVER_ID" => tid.to_s ,"REDIS_URL" => redis_url, "LOG_LOCATION" => (log_location == STDOUT ? nil : log_location) }, cmd)
      end
    end

  end

end
