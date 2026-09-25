
module Haystack
  module Rails
    module Middleware
      class Injector
        def initialize(app)
          @app = app
        end

        ERROR_EVENT_ID_HEADER = 'X-Haystack-Event-Id'
        BUNDLE_ASSET = 'haystack/bundle.tracing.replay.min.js'

        def call(env)
          status, headers, response = @app.call(env)

          # Avisa o SDK do navegador que esta requisição gerou um erro no
          # backend: ele envia o replay do último minuto (ver generate_script)
          error_event_id = backend_error_event_id(env)
          headers[ERROR_EVENT_ID_HEADER] = error_event_id if error_event_id

          if html_response?(headers)
            begin
              body_content = extract_body(response)
              response_body = inject_script(body_content, env, error_event_id)
              headers['Content-Length'] = response_body.bytesize.to_s
              # O corpo original precisa ser fechado: é o close que encerra a
              # requisição no Rails (executor/reloader); sem ele o lock de
              # recarga fica preso e o app trava em development
              response.close if response.respond_to?(:close)
              response = [response_body]
            rescue => e
              # A injeção do SDK nunca deve derrubar a página
              ::Rails.logger.warn("[Haystack] falha ao injetar o SDK JS: #{e.class}: #{e.message}")
            end
          end

          [status, headers, response]
        end

        private

        def resolve_setting(value)
          value.respond_to?(:call) ? value.call : value
        rescue StandardError => e
          ::Rails.logger.warn("[Haystack] configuração do replay indisponível: #{e.class}: #{e.message}")
          nil
        end

        def backend_error_event_id(env)
          event_id = env[Haystack::Rack::CaptureExceptions::ERROR_EVENT_ID_KEY]
          event_id if event_id.is_a?(String) && event_id.match?(/\A[0-9a-f]{32}\z/)
        end

        def html_response?(headers)
          headers['Content-Type']&.include?('text/html')
        end

        def extract_body(response)
          # Se response responde a :body, usamos isso; caso contrário, se for um array, juntamos os elementos.
          if response.respond_to?(:body)
            response.body.to_s
          elsif response.respond_to?(:join)
            response.join
          else
            response.to_s
          end
        end

        def inject_script(body, env, error_event_id = nil)
          config = Haystack.instance_variable_get(:@global_configuration)

          dsn = same_origin_dsn(config.js.dsn || ENV['HAYSTACK_DSN'], env)

          script_content = generate_script(
            config: config,
            dsn: dsn,
            user_data: fetch_user_data(env, config),
            session_data: fetch_session_data(env),
            flash_messages: fetch_flash_messages(env),
            request_params: fetch_request_params(env),
            error_event_id: error_event_id
          )

          body.sub('</head>', "#{script_content}\n</head>")
        end

        # Se a DSN aponta para o próprio host da página, usa o protocolo/porta da
        # página: evita mixed content (http -> https) e certificado não confiável
        def same_origin_dsn(dsn, env)
          return dsn if dsn.blank?

          uri = URI.parse(dsn)
          request = ActionDispatch::Request.new(env)
          return dsn unless uri.host == request.host

          userinfo = "#{uri.userinfo}@" if uri.userinfo
          "#{request.scheme}://#{userinfo}#{request.host_with_port}#{uri.path}"
        rescue URI::InvalidURIError
          dsn
        end

        def fetch_request_params(env)
          controller = env['action_controller.instance']
          return {} unless controller

          # Mesmo filtro dos logs do Rails (filter_parameters), em todos os níveis
          params = controller.params.to_unsafe_h.except(:controller, :action)
          ActiveSupport::ParameterFilter.new(::Rails.application.config.filter_parameters)
            .filter(params)
            .deep_transform_keys { |k| k.to_s.underscore }
        rescue => e
          { error: "params_error: #{e.message}" }
        end

        # Obtém a instância do usuário atual do controller
        def fetch_current_user(env)
          controller = env['action_controller.instance']
          return unless controller

          instance_variables = controller.instance_variables.each_with_object({}) do |var, hash|
            hash[var.to_s] = controller.instance_variable_get(var)
          end

          instance_variables['@current_user']
        end

        # Constrói os dados do usuário com base nas configurações dinâmicas
        def fetch_user_data(env, config)
          current_user = fetch_current_user(env)
          return {} unless current_user

          ip_address = env['action_controller.instance']&.request&.remote_ip

          {
            id: current_user.id,
            username: fetch_user_attribute(current_user, config.js.user_name_method, :name),
            email: fetch_user_attribute(current_user, config.js.user_email_method, :email),
            url: fetch_user_url(current_user, config.js.user_url_method, env),
            image_url: fetch_user_attribute(current_user, config.js.user_image_method, :avatar_image_url),
            ip_address: ip_address
          }
        end

        # Obtém um atributo do usuário de forma segura
        def fetch_user_attribute(user, method, default)
          return unless user
          method ||= default
          user.public_send(method) if user.respond_to?(method)
        end

        # Obtém a URL do usuário de forma segura
        def fetch_user_url(user, method, env)
          return unless user && method

          request = ActionDispatch::Request.new(env)
          ::Rails.application.routes.url_helpers.public_send(method, user, host: request.host, port: request.optional_port, protocol: request.protocol)
        rescue StandardError
          nil
        end

        # Captura os dados da sessão
        def fetch_session_data(env)
          session = env['rack.session'] || {}

          warden_user = session['warden.user.user.key']

          processed_warden = if warden_user && warden_user.is_a?(Array) && warden_user[0].is_a?(Array)
                                {
                                  user_id: warden_user.dig(0, 0)&.to_s
                                }
                              else
                                warden_user.to_s
                              end

          # Captura chaves padrão da sessão
          session_info = {
            session_id: session['session_id'],
            warden_user: processed_warden
          }

          # Captura chaves do Devise Masquerade (caso esteja personificando outro usuário)
          masquerade_keys = session.keys.select { |key| key.to_s.start_with?('devise_masquerade_') }
          masquerade_data = masquerade_keys.each_with_object({}) do |key, hash|
            hash[key] = session[key]
          end

          masquerade_data = {'masquerade_data': masquerade_data}

          # Junta os dados da sessão com os de masquerading
          session_info.merge!(masquerade_data).compact
        end

        # Captura as mensagens flash
        def fetch_flash_messages(env)
          flash_hash = env['action_dispatch.request.flash_hash']
          return {} unless flash_hash

          {
            notice: flash_hash[:notice],
            alert: flash_hash[:alert]
          }.compact
        end

        # Gera o script que será injetado no HTML
        # Com Turbolinks o <script> inline do <head> roda de novo a cada visita,
        # mas o SDK só aceita uma instância de replay: inicializa uma vez e, nas
        # visitas seguintes, só atualiza usuário e contextos da página atual.
        #
        # Replay de erro: o SDK guarda o último minuto em buffer. Quando há um
        # erro (de JS, ou do backend avisado pelo header X-Haystack-Event-Id numa
        # resposta de XHR/fetch, como as visitas do Turbolinks), o buffer é
        # enviado e a gravação continua por replay_after_error_seconds; depois o
        # replay é encerrado e um buffer novo começa, pronto para o próximo erro.
        def generate_script(config:, dsn:, user_data:, session_data:, flash_messages:, request_params:, error_event_id: nil)
          after_error_ms = (config.js.replay_after_error_seconds || 30).to_i * 1000
          # Caminho com digest (em produção só existe a versão precompilada com
          # digest; /assets/haystack/bundle...js daria 404)
          bundle_path = ::ActionController::Base.helpers.asset_path(BUNDLE_ASSET)
          # As taxas podem ser lambdas, avaliadas a cada página (ex.: lidas da
          # configuração do projeto); com as duas em zero o replay nem é ligado
          session_rate = resolve_setting(config.js.replays_session_sample_rate).to_f
          error_rate = resolve_setting(config.js.replays_on_error_sample_rate)
          error_rate = error_rate.nil? ? 1.0 : error_rate.to_f
          replay_integration = if session_rate.positive? || error_rate.positive?
            <<~JS.strip
              HS.replayIntegration({
                        maskAllText: #{config.js.mask_all_text.nil? ? false : config.js.mask_all_text},
                        blockAllMedia: #{config.js.block_all_media.nil? ? true : config.js.block_all_media},
                        mutationLimit: #{config.js.mutation_limit.to_i},
                        mutationBreadcrumbLimit: #{config.js.mutation_breadcrumb_limit.to_i},
                        // Buffer síncrono: o bundle (patch do Haystack) mantém nele de 60
                        // a 120 s antes do erro; o buffer compactado do worker não permite
                        // descartar só o trecho antigo e voltaria a guardar de 0 a 60 s
                        useCompression: false,
                      }),
            JS
          end

          <<~SCRIPT
            <script src="#{bundle_path}"></script>
            <script>
              (function () {
                if (!window.Haystack) return;
                var HS = window.Haystack;

                if (!window.__haystackInitialized) {
                  window.__haystackInitialized = true;

                  HS.init({
                    dsn: #{dsn.to_s.to_json},
                    replaysSessionSampleRate: #{session_rate},
                    replaysOnErrorSampleRate: #{error_rate},
                    environment: #{(config.js.environment || ::Rails.env).to_s.to_json},
                    tracesSampleRate: #{config.js.traces_sample_rate || 1},
                    integrations: [
                      #{replay_integration}
                      HS.browserTracingIntegration(),
                    ]
                  });

                  var afterErrorMs = #{after_error_ms};
                  var stopTimer = null;
                  var seenBackendErrors = {};

                  var replay = function () { return HS.getReplay && HS.getReplay(); };
                  // Só encerra replays que começaram por erro; sessões amostradas seguem
                  var startedByError = function (r) {
                    var session = r && r._replay && r._replay.session;
                    return !!session && session.sampled === 'buffer';
                  };

                  // O prazo fica no sessionStorage: um recarregamento de página
                  // perde o timer, mas o SDK retoma o replay da sessão
                  var STOP_KEY = 'haystackReplayStopAt';
                  var readStopAt = function () {
                    try { return parseInt(sessionStorage.getItem(STOP_KEY) || '0', 10); } catch (e) { return 0; }
                  };
                  var writeStopAt = function (stopAt) {
                    try {
                      if (stopAt) { sessionStorage.setItem(STOP_KEY, String(stopAt)); } else { sessionStorage.removeItem(STOP_KEY); }
                    } catch (e) {}
                  };

                  var armStop = function (stopAt) {
                    clearTimeout(stopTimer);
                    stopTimer = setTimeout(function () {
                      writeStopAt(0);
                      var r = replay();
                      if (!startedByError(r)) return;
                      Promise.resolve(r.stop()).then(function () { r.startBuffering(); });
                    }, Math.max(0, stopAt - Date.now()));
                  };

                  var scheduleStop = function () {
                    if (!startedByError(replay())) return;
                    var stopAt = Date.now() + afterErrorMs;
                    writeStopAt(stopAt);
                    armStop(stopAt);
                  };

                  // Página nova no meio de um replay de erro: retoma o prazo (ou
                  // encerra já, se ele passou ou se não há prazo registrado)
                  setTimeout(function () {
                    var r = replay();
                    var stopAt = readStopAt();
                    if (r && r._replay && r._replay.recordingMode === 'session' && startedByError(r)) {
                      armStop(stopAt || Date.now());
                    } else if (stopAt) {
                      writeStopAt(0);
                    }
                  }, 1000);

                  var onBackendError = function (eventId) {
                    if (!eventId || seenBackendErrors[eventId]) return;
                    seenBackendErrors[eventId] = true;
                    var r = replay();
                    if (!r || !r._replay) return;
                    // Liga o erro do backend a este replay (vai em error_ids)
                    try { r._replay.getContext().errorIds.add(eventId); } catch (e) {}
                    Promise.resolve(r.flush()).then(scheduleStop);
                  };
                  window.__haystackBackendError = onBackendError;

                  HS.getClient().on('afterSendEvent', function (event) {
                    if (!event.type && event.exception) setTimeout(scheduleStop, 0);
                  });

                  var send = XMLHttpRequest.prototype.send;
                  XMLHttpRequest.prototype.send = function () {
                    this.addEventListener('loadend', function () {
                      try { onBackendError(this.getResponseHeader(#{ERROR_EVENT_ID_HEADER.to_json})); } catch (e) {}
                    });
                    return send.apply(this, arguments);
                  };

                  if (window.fetch) {
                    var fetch = window.fetch;
                    window.fetch = function () {
                      return fetch.apply(this, arguments).then(function (response) {
                        try { onBackendError(response.headers.get(#{ERROR_EVENT_ID_HEADER.to_json})); } catch (e) {}
                        return response;
                      });
                    };
                  }
                }

                HS.setUser(#{user_data.any? ? user_data.to_json : 'null'});
                HS.setContext('session', #{session_data.any? ? session_data.to_json : 'null'});
                HS.setContext('flash_messages', #{flash_messages.any? ? flash_messages.to_json : 'null'});
                HS.setContext('request_params', #{request_params.any? ? request_params.to_json : 'null'});
                #{error_event_id ? "window.__haystackBackendError(#{error_event_id.to_json});" : ''}
              })();
            </script>
          SCRIPT
        end
      end
    end
  end
end
