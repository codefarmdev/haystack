require 'haystack'
require 'benchmark'

class ::Haystack::Event::ActiveRecordEvent
  def connection_config; {:adapter => 'mysql'}; end
end

GC.disable

namespace :benchmark do
  task :all => [:run_inactive, :run_active] do
  end

  task :run_inactive do
    puts 'Running with haystack off'
    ENV['HAYSTACK_PUSH_API_KEY'] = nil
    subscriber = ActiveSupport::Notifications.subscribe do |*args|
      # Add a subscriber so we can track the overhead of just haystack
    end
    run_benchmark
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  task :run_active do
    puts 'Running with haystack on'
    ENV['HAYSTACK_PUSH_API_KEY'] = 'something'
    run_benchmark
  end
end

def run_benchmark
  total_objects = ObjectSpace.count_objects[:TOTAL]
  puts "Initializing, currently #{total_objects} objects"
  Haystack.config = Haystack::Config.new('', 'production')
  Haystack.start
  puts "Haystack #{Haystack.active? ? 'active' : 'not active'}"

  puts 'Running 10_000 normal transactions'
  puts(Benchmark.measure do
    10_000.times do |i|
      Haystack::Transaction.create("transaction_#{i}", {})

      ActiveSupport::Notifications.instrument('sql.active_record', :sql => 'SELECT `users`.* FROM `users` WHERE `users`.`id` = ?')
      10.times do
        ActiveSupport::Notifications.instrument('sql.active_record', :sql => 'SELECT `todos`.* FROM `todos` WHERE `todos`.`id` = ?')
      end

      ActiveSupport::Notifications.instrument('render_template.action_view', :identifier => 'app/views/home/show.html.erb') do
        5.times do
          ActiveSupport::Notifications.instrument('render_partial.action_view', :identifier => 'app/views/home/_piece.html.erb') do
            3.times do
              ActiveSupport::Notifications.instrument('cache.read')
            end
          end
        end
      end

      ActiveSupport::Notifications.instrument(
        'process_action.action_controller',
        :controller => 'HomeController',
        :action     => 'show',
        :params     => {:id => 1}
      )

      Haystack::Transaction.complete_current!
    end
  end)

  if Haystack.active?
    puts "Running aggregator post_processed_queue! for #{Haystack.agent.aggregator.queue.length} transactions"
    puts(Benchmark.measure do
      Haystack.agent.aggregator.post_processed_queue!.to_json
    end)
  end

  puts "Done, currently #{ObjectSpace.count_objects[:TOTAL] - total_objects} objects created"
end
