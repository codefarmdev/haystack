require 'drb/drb'

module Haystack
  class IPC
    class << self
      def forked!
        Server.stop
        Client.start
        Haystack.agent.stop_thread
      end
    end

    class Server
      class << self
        attr_reader :uri

        def start
          local_tmp_path = File.join(Haystack.config.root_path, 'tmp')
          if File.exists?(local_tmp_path)
            @uri = 'drbunix:' + File.join(local_tmp_path, "haystack-#{Process.pid}")
          else
            @uri = "drbunix:/tmp/haystack-#{Process.pid}"
          end

          Haystack.logger.info("Starting IPC server, listening on #{uri}")
          DRb.start_service(uri, Haystack::IPC::Server)
        end

        def stop
          Haystack.logger.debug('Stopping IPC server')
          DRb.stop_service
        end

        def enqueue(transaction)
          Haystack.logger.debug("Receiving transaction #{transaction.request_id} in IPC server")
          Haystack.enqueue(transaction)
        end
      end
    end

    class Client
      class << self
        attr_reader :server

        def start
          Haystack.logger.debug('Starting IPC client')
          @server = DRbObject.new_with_uri(Haystack::IPC::Server.uri)
          @active = true
        end

        def stop
          Haystack.logger.debug('Stopping IPC client')
          @server = nil
          @active = false
        end

        def enqueue(transaction)
          Haystack.logger.debug("Sending transaction #{transaction.request_id} in IPC client")
          @server.enqueue(transaction)
        end

        def active?
          !! @active
        end
      end
    end
  end
end
