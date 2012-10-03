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

  # Disable ruby-smpp logging
  require 'tempfile'
  Smpp::Base.logger = Logger.new(Tempfile.new('ruby-smpp').path)

  LIB_PATH = File.dirname(__FILE__) + '/rocket_sms/'

  %w{ gateway did message transceiver scheduler lock }.each do |dep|
    require LIB_PATH + dep
  end

  def start
    @pid = Process.pid
    #Process.daemon
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

  def settings=(yaml_file_location)
    @settings = symbolize_keys(YAML.load(IO.read(yaml_file_location)))
    redis_url = @settings[:redis] && @settings[:redis][:url]
    log_location = @settings[:log] && @settings[:log][:location]
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
    @logger ||= Logger.new(log_location)
  end

  def log_location
    @log_location ||= STDOUT
  end

  def log_location=(location)
    @log_location = location unless location.nil?
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
