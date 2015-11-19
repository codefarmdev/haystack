if defined?(::Unicorn)
  Haystack.logger.info('Loading Unicorn integration')

  # We'd love to be able to hook this into Unicorn in a less
  # intrusive way, but this is the best we can do given the
  # options we have.

  class Unicorn::HttpServer
    alias_method :original_worker_loop, :worker_loop

    def worker_loop(worker)
      Haystack.agent.forked!
      original_worker_loop(worker)
    end
  end

  class Unicorn::Worker
    alias_method :original_close, :close

    def close
      Haystack.agent.shutdown(true, 'stopping Unicorn worker process')
      original_close
    end
  end
end
