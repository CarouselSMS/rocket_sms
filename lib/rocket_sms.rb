require 'rubygems'
require 'bundler/setup'
require 'eventmachine'
require 'smpp'
require 'em-hiredis'
require 'oj'
require 'multi_json'
require 'singleton'
require 'securerandom'
require 'ostruct'

require "rocket_sms/version"

module RocketSMS

  # Disable ruby-smpp logging
  require 'tempfile'
  Smpp::Base.logger = Logger.new(Tempfile.new('ruby-smpp').path)

  LIB_PATH = File.dirname(__FILE__) + '/rocket_sms/'

  %w{ gateway did message transceiver scheduler lock }.each do |dep|
    require LIB_PATH + dep
  end

  def self.start
    
  end

  def self.queues
    @@queues ||= {
      mt: {
        pending: 'gateway:queues:mt:pending',
        retries: 'gateway:queues:mt:retries',
        success: 'gateway:queues:mt:success',
        failure: 'gateway:queues:mt:failure'
      },
      mo: 'gateway:queues:mo:received'
    }
  end

  def self.gateway
    @@gateway ||= RocketSMS::Gateway.instance
  end

  def self.pids
    @@pids ||= { scheduler: nil, transceivers: { } }
  end

  def self.redis
    @@redis ||= EM::Hiredis.connect(redis_url)
  end

  # Configuration and Setup
  def self.configure
    yield self
  end

  def self.configurations=(yaml_file_location)
    @@configurations = YAML.load(IO.read(yaml_file_location))
  end

  def self.configurations
    @@configurations
  end

  def self.redis_url
    @@redis_url
  end

  def self.redis_url=(url)
    @@redis_url = url
  end

  def self.logger
    @@logger ||= Logger.new(STDOUT)
  end

  def self.log=(location)
    @@logger = Logger.new(location)
  end

end
