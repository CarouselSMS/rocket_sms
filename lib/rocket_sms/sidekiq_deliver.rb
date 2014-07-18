module StatusProcessor
  class Success
    include Sidekiq::Worker
    def perform(*args)
      # stub
    end
  end

  class Failure
    include Sidekiq::Worker
    def perform(*args)
      # stub
    end
  end
end

class Receiver
  include Sidekiq::Worker
  def perform(*args)
    # stub
  end
end

class SidekiqDeliver
  def self.register_message_accepted(*args)
    StatusProcessor::Success.perform_async(*args)
  end

  def self.register_message_rejected(*args)
    StatusProcessor::Failure.perform_async(*args)
  end

  def self.register_message_received(*args)
    Receiver.perform_async(*args)
  end
end
