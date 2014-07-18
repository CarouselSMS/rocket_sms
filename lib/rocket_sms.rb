require 'rubygems'
require 'bundler/setup'
require 'eventmachine'
require 'em-hiredis'
require 'oj'
require 'multi_json'
require 'singleton'
require 'securerandom'
require 'ostruct'
require 'forwardable'
#require 'smpp'

path = File.expand_path(__FILE__).split('/')
path.delete_at(-1)
path.delete_at(-1)
path = path.join('/')

require "#{path}/vendor/ruby-smpp/lib/smpp.rb"

require "rocket_sms/version"

module RocketSMS
  extend self


  LIB_PATH = File.dirname(__FILE__) + '/rocket_sms/'

  %w{ gateway did message sidekiq_deliver transceiver scheduler lock }.each do |dep|
    require LIB_PATH + dep
  end

  def start
    @pid = Process.pid
    Smpp::Base.logger = self.logger
    gateway.start
  end

  def queues
    @queues ||= {
      mt: {
        pending: 'gateway:queues:mt:pending',
        success: 'gateway:queues:mt:success',
        failure: 'gateway:queues:mt:failure'
      },
      mo: 'gateway:queues:mo:received',
      dr: 'gateway:queues:dr'
    }
  end

  def gateway
    @gateway ||= RocketSMS::Gateway.instance
  end

  def redis
    @redis ||= EM::Hiredis.connect(redis_url)
  end

  # Configuration and Setup
  def configure
    yield self
  end

  def settings=(duck)
    @settings = symbolize_keys(duck.is_a?(Hash) ? duck : YAML.load(IO.read(duck)))
    self.redis_url = @settings[:redis] && @settings[:redis][:url]
  end

  def settings
    @settings
  end

  def redis_url
    @redis_url ||= "redis://localhost:6379"
  end

  def redis_url=(url)
    @redis_url = url unless url.nil?
  end

  def logger
    @logger ||= Logger.new(log_location).tap { |l| l.level = log_level }
  end

  def log_location
    @log_location ||= STDOUT
  end

  def log_location=(location)
    log_location.sync = true if log_location.respond_to? :sync=
    @log_location = location unless location.nil?
  end

  def log_level
    @log_level ||= Logger::INFO
  end

  def log_level=(level)
    @log_level = level
  end

  def symbolize_keys(hash)
    hash.inject({}){|result, (key, value)|
      new_key = case key
                when String then key.to_sym
                else key
                end
      new_value = case value
                  when Hash then symbolize_keys(value)
                  else value
                  end
      result[new_key] = new_value
      result
    }
  end

end
