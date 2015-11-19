module TransactionHelpers
  def fixed_time
    @fixed_time ||= Time.utc(2014, 01, 15, 11, 0, 0).to_f
  end

  def uploaded_file
    if rails_present?
      ActionDispatch::Http::UploadedFile.new(:tempfile => '/tmp')
    else
      ::Rack::Multipart::UploadedFile.new(File.join(fixtures_dir, '/uploaded_file.txt'))
    end
  end

  def transaction_with_exception
    haystack_transaction(:process_action_event => notification_event).tap do |o|
      o.set_tags('user_id' => 123)
      begin
        raise ArgumentError, 'oh no'
      rescue ArgumentError => exception
        exception.stub(:backtrace => [
          File.join(project_fixture_path, 'app/controllers/somethings_controller.rb:10').to_s,
          '/user/local/ruby/path.rb:8'
        ])
        o.add_exception(exception)
      end
    end
  end

  def regular_transaction
    haystack_transaction(:process_action_event => notification_event)
  end

  def regular_transaction_with_x_request_start
    haystack_transaction(
      :process_action_event => notification_event,
      'HTTP_X_REQUEST_START' => "t=#{((fixed_time - 0.04) * 1000).to_i}"
    )
  end

  def slow_transaction(args={})
    haystack_transaction(
      {
        :process_action_event => notification_event(
          :start => fixed_time,
          :ending => fixed_time + Haystack.config[:slow_request_threshold] / 999.99
        )
      }.merge(args)
    )
  end

  def slower_transaction(args={})
    haystack_transaction(
      {
        :process_action_event => notification_event(
          :start => fixed_time,
          :ending => fixed_time + Haystack.config[:slow_request_threshold] / 499.99
        )
      }.merge(args)
    )
  end

  def background_job_transaction(args={}, payload=create_background_payload)
    Haystack::Transaction.create(
      '1',
      {
        'SERVER_NAME' => 'localhost',
        'action_dispatch.routes' => 'not_available'
      }.merge(args)
    ).tap do |o|
      o.set_perform_job_event(
        notification_event(
          :name => 'perform_job.delayed_job',
          :payload => payload
        )
      )
    end
  end

  def haystack_transaction(args={})
    process_action_event = args.delete(:process_action_event)
    events = args.delete(:events) || [
      notification_event(:name => 'query.mongoid')
    ]
    exception = args.delete(:exception)
    defaults = args.delete(:defaults) || {}
    Haystack::Transaction.create(
      '1',
      {
        'HTTP_USER_AGENT' => 'IE6',
        'SERVER_NAME' => 'localhost',
        'action_dispatch.routes' => 'not_available'
      }.merge(args),
      defaults
    ).tap do |o|
      o.set_process_action_event(process_action_event)
      o.add_exception(exception)
      events.each { |event| o.add_event(event) }
    end
  end
end
