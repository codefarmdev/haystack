class Haystack::Event < ActiveSupport::Notifications::Event
  def sanitize!
    @payload = Haystack::ParamsSanitizer.sanitize(@payload)
  end

  def truncate!
    @payload = {}
  end

  def self.event_for_instrumentation(*args)
    case args[0]
    when 'query.moped'
      Haystack::Event::MopedEvent.new(*args)
    else
      new(*args)
    end
  end
end

require 'haystack/event/moped_event'
