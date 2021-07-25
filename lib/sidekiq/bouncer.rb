require 'sidekiq/bouncer/config'
require 'sidekiq/bouncer/version'

module Sidekiq
  class Bouncer
    BUFFER = 0.01 # Second.
    SKIP_BUFFER = 2 # Second.
    DEFAULT_DELAY = 60 # Seconds.

    class << self
      def config
        @config ||= Config.new
      end

      def configure(&block)
        yield config
      end
    end

    def initialize(klass, delay = DEFAULT_DELAY)
      @klass = klass
      @delay = delay
    end

    def first_run?(*params)
      self.class.config.redis.get(first_run_key(params)).blank?
    end

    def first_run_or_debounce(*params)
      if first_run?(*params)
        self.class.config.redis.set(first_run_key(params), 1)
        @klass.perform_async(*params)
        return
      end

      debounce(*params)
    end

    def skip_job?(*params)
      timestamp = self.class.config.redis.get(key(params))
      timestamp.present? && timestamp.to_f + SKIP_BUFFER > now + @delay
    end

    def debounce(*params)
      if skip_job?(*params)
        return
      end

      self.class.config.redis.set(key(params), now + @delay)

      # Schedule the job with not only debounce delay added, but also BUFFER.
      # BUFFER helps prevent race condition between this line and the one above.
      @klass.perform_at(now + @delay + BUFFER, *params)
    end

    def let_in?(*params)
      # Only the last job should come after the timestamp.
      timestamp = self.class.config.redis.get(key(params))
      first_run = self.class.config.redis.get(first_run_key(params))

      # Support first run
      if timestamp.nil? && first_run.present?
        return true
      end

      return false if Time.now.to_f < timestamp.to_f

      self.class.config.redis.del(key(params))
      self.class.config.redis.del(first_run_key(params))

      true
    end

    private

    def key(params)
      "#{@klass}:#{params.join(',')}"
    end

    def first_run_key(params)
      "fr:#{@klass}:#{params.join(',')}"
    end

    def now
      Time.now.to_f
    end
  end
end
