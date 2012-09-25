require 'rubygems'
require 'bundler/setup'
require 'eventmachine'
require 'smpp'
require 'em-hiredis'
require 'oj'
require 'multi_json'
require 'singleton'
require 'securerandom'

require "lean_sms/version"

module LeanSMS

  # Disable ruby-smpp logging
  require 'tempfile'
  Smpp::Base.logger = Logger.new(Tempfile.new('ruby-smpp').path)

  LIB_PATH = File.dirname(__FILE__) + '/lean_sms/'

  %w{ gateway did message transceiver scheduler configurator }.each do |dep|
    require LIB_PATH + dep
  end

  def self.configure
    yield self
  end

end
