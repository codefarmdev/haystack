module Rake
  class Task
    alias_method :invoke_without_haystack, :invoke

    def invoke(*args)
      if Haystack.active?
        invoke_with_haystack(*args)
      else
        invoke_without_haystack(*args)
      end
    end

    def invoke_with_haystack(*args)
      transaction = Haystack::Transaction.create(
        SecureRandom.uuid,
        ENV,
        :kind => 'background_job',
        :action => name,
        :params => args
      )

      invoke_without_haystack(*args)
    rescue => exception
      unless Haystack.is_ignored_exception?(exception)
        transaction.add_exception(exception)
      end
      raise exception
    ensure
      transaction.complete!
      Haystack.agent.send_queue if Haystack.active?
    end
  end
end
