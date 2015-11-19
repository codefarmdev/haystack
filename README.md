Haystack agent
=================

This gem collects error and performance data from your Rails
applications and sends it to [Haystack](http://farmer.codefarm.com.br)

## Pull requests / issues

New features should be made in an issue or pullrequest. Title format is as follows:

    name [request_count]

example

    tagging [2]

## Postprocessing middleware

Haystack sends Rails
[ActiveSupport::Notification](http://api.rubyonrails.org/classes/ActiveSupport/Notifications.html)-events
to Haystack over SSL. These events contain basic metadata such as a name
and timestamps, and additional 'payload' log data. Haystack uses a postprocessing
middleware stack to clean up events before they get sent to haystack.com. You
can add your own middleware to this stack in `config/environment/my_env.rb`.

### Examples

#### Minimal template

```ruby
class MiddlewareTemplate
  def call(event)
    # modify the event in place
    yield # pass control to the next middleware
    # modify the event some more
  end
end

Haystack.post_processing_middleware.add MiddlewareTemplate
```

#### Remove boring payloads

```ruby
class RemoveBoringPayload
  def call(event)
    event.payload.clear unless event.name == 'interesting'
    yield
  end
end
```

## Development

Run rake bundle or, or run bundle install for all Gemfiles:

```
bundle --gemfile gemfiles/capistrano2.gemfile
bundle --gemfile gemfiles/capistrano3.gemfile
bundle --gemfile gemfiles/no_dependencies.gemfile
bundle --gemfile gemfiles/rails-3.0.gemfile
bundle --gemfile gemfiles/rails-3.1.gemfile
bundle --gemfile gemfiles/rails-3.2.gemfile
bundle --gemfile gemfiles/rails-4.0.gemfile
bundle --gemfile gemfiles/rails-4.1.gemfile
bundle --gemfile gemfiles/rails-4.2.gemfile
bundle --gemfile gemfiles/sinatra.gemfile
```

To run the spec suite with a specific Gemfile:

```
BUNDLE_GEMFILE=gemfiles/capistrano2.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/capistrano3.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/no_dependencies.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-3.0.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-3.1.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-3.2.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-4.0.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-4.1.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-4.2.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/sinatra.gemfile bundle exec rspec
```

Or run `rake generate_bundle_and_spec_all` to generate a script that runs specs for all
Ruby versions and gem combinations we support.
You need Rvm or Rbenv to do this. Travis will run specs for these combinations as well.
