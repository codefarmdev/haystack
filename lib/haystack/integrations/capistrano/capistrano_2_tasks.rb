module Haystack
  module Integrations
    class Capistrano
      def self.tasks(config)
        config.load do
          after 'deploy', 'haystack:deploy'
          after 'deploy:migrations', 'haystack:deploy'

          namespace :haystack do
            task :deploy do
              env = fetch(:rails_env, fetch(:rack_env, 'production'))
              user = ENV['USER'] || ENV['USERNAME']
              revision = fetch(:haystack_revision, fetch(:current_revision))

              haystack_config = Haystack::Config.new(
                ENV['PWD'],
                env,
                fetch(:haystack_config, {}),
                logger
              )

              if haystack_config && haystack_config.active?
                marker_data = {
                  :revision => revision,
                  :user => user
                }

                marker = Marker.new(marker_data, haystack_config, logger)
                if config.dry_run
                  logger.info('Dry run: Deploy marker not actually sent.')
                else
                  marker.transmit
                end
              end
            end
          end
        end
      end
    end
  end
end

if ::Capistrano::Configuration.instance
  Haystack::Integrations::Capistrano.tasks(::Capistrano::Configuration.instance)
end
