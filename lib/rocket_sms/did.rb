module RocketSMS
  class Did

    attr_reader :params

    def initialize(params)
      @params = OpenStruct.new(params)
    end

    def to_json
      MultiJson.dump(@params.marshal_dump)
    end

    def self.from_json(json)
      params = MultiJson.load(json, symbolize_keys: true)
      did = Did.new(params)
      return did
    end

    def method_missing(sym, *args, &block)
      @params.send(sym, *args, &block)
    end

  end
end
