module Sidekiq
  class Bouncer
    class Config
      attr_accessor :redis
    end

    private_constant :Config
  end
end
