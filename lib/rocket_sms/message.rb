require 'ostruct'

module RocketSMS
  class Message

    attr_reader :params

    def initialize(params)
      @params = OpenStruct.new(params)
      @params.pass ||= 0
    end

    def to_json
      MultiJson.dump(@params.marshal_dump)
    end

    def add_pass
      @params.pass += 1
    end

    def self.from_json(json)
      params = MultiJson.load(json, symbolize_keys: true)
      msg = Message.new(params)
      return msg
    end

    def method_missing(sym, *args, &block)
      @params.send(sym, *args, &block)
    end

  end
end
