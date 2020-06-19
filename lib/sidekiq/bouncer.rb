require 'sidekiq/bouncer/version'

module Sidekiq
  class Bouncer
    BUFFER = 1 # Second.
    DEFAULT_DELAY = 60 # Seconds.

    def initialize(klass, delay = DEFAULT_DELAY)
      @klass = klass
      @delay = delay
    end

    def debounce(*params)
      # Refresh the timestamp in redis with debounce delay added.
      ::Rails.application.redis.set(key(params), now + @delay)

      # Schedule the job with not only debounce delay added, but also BUFFER.
      # BUFFER helps prevent race condition between this line and the one above.
      @klass.perform_at(now + @delay + BUFFER, *params)
    end

    def let_in?(*params)
      # Only the last job should come after the timestamp.
      timestamp = ::Rails.application.redis.get(key(params))
      return false if Time.now.to_i < timestamp.to_i

      # But because of BUFFER, there could be mulitple last jobs enqueued within
      # the span of BUFFER. The first one will clear the timestamp, and the rest
      # will skip when they see that the timestamp is gone.
      return false if timestamp.nil?
      ::Rails.application.redis.del(key(params))

      true
    end

    private

    def key(params)
      "#{@klass}:#{params.join(',')}"
    end

    def now
      Time.now.to_i
    end
  end
end
