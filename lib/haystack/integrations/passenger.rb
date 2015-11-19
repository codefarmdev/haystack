if defined?(::PhusionPassenger)
  Haystack.logger.info('Loading Passenger integration')

  ::PhusionPassenger.on_event(:starting_worker_process) do |forked|
    Haystack.logger.debug('starting worker process')
    Haystack.agent.forked!
  end

  ::PhusionPassenger.on_event(:stopping_worker_process) do
    Haystack.logger.debug('stopping worker process')
    Haystack.agent.shutdown(true, 'stopping Passenger worker process')
  end
end
