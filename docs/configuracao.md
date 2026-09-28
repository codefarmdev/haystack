# Configuração

Tudo fica no bloco `Haystack.init` do `config/initializers/haystack.rb`. As
opções são as do sentry-ruby 5.22 (a [documentação do Sentry para
Ruby](https://docs.sentry.io/platforms/ruby/configuration/options/) vale,
trocando `Sentry` por `Haystack`); aqui estão as que usamos e as que o
Haystack acrescenta.

## Backend

| Opção | Padrão | Para que serve |
|---|---|---|
| `dsn` | `ENV['HAYSTACK_DSN']` | endereço do Farmer + token do projeto |
| `enabled_environments` | todos | ambientes que enviam dados (ex.: `%w[production]`) |
| `environment` | `RAILS_ENV` | nome do ambiente mostrado no Farmer |
| `release` | detectado (`REVISION` do Capistrano, git) | versão do app em cada erro |
| `traces_sample_rate` | `nil` (sem transações) | fração das requisições medidas (`1.0` = todas) |
| `traces_sampler` | — | lambda que decide por requisição (tem prioridade sobre a taxa) |
| `excluded_exceptions` | erros de "página não existe" do Rails | classes que nunca são enviadas |
| `before_send` | — | lambda para alterar ou descartar (`nil`) um erro antes do envio |
| `before_send_transaction` | — | idem para transações (substitui o `ignore_actions` do 0.x) |
| `breadcrumbs_logger` | `[]` | rastro antes do erro: `:active_support_logger` (queries, views), `:http_logger` (chamadas HTTP) |
| `context_lines` | 3 | linhas de código ao redor de cada frame do stacktrace |
| `include_local_variables` | `false` | valores das variáveis locais nos frames. **Cuidado:** não passam pelo `filter_parameters`; uma variável `senha` apareceria no Farmer |
| `send_default_pii` | `false` | com `true`, manda params e path sem filtro. Deixe `false` |
| `send_modules` | `true` | lista de gems em cada erro (o Farmer não usa; `false` economiza) |
| `background_worker_threads` | metade dos CPUs | envio em segundo plano; `0` envia na hora (bom em testes) |
| `debug` | `false` | loga cada envio (útil para investigar "não chega nada") |

O `haystack-rails` também usa o `config.filter_parameters` do app para
filtrar params e sessão em erros, transações e no navegador.

### O que vai em cada erro e transação

- exceção, stacktrace com código, breadcrumbs, ambiente, release e servidor;
- `request`: URL, método, headers e o path filtrado;
- `extra.params`: params filtrados, sem `controller`/`action`;
- `extra.session_data`: sessão filtrada, sem o token CSRF;
- `extra.client_ip`: IP do cliente;
- `extra.memory_usage`: memória do processo em MB (só Linux);
- nas transações: tempo total, spans de SQL e views, `view_runtime`.

## Navegador (`config.js`)

Valem para o SDK que o `haystack-rails` injeta nas páginas HTML.

| Opção | Padrão | Para que serve |
|---|---|---|
| `js.dsn` | a DSN do backend | outra DSN para o navegador (ex.: outro protocolo) |
| `js.environment` | `Rails.env` | ambiente dos eventos do navegador |
| `js.traces_sample_rate` | `1` | fração dos carregamentos de página medidos |
| `js.replays_on_error_sample_rate` | `1` | fração dos erros que enviam replay |
| `js.replays_session_sample_rate` | `0` | fração das sessões gravadas inteiras, mesmo sem erro |
| `js.replay_after_error_seconds` | `30` | quanto a gravação continua depois do erro (mínimo 6) |
| `js.mask_all_text` | `false` | troca todo texto da tela por `*` no replay |
| `js.block_all_media` | `true` | não grava imagens e vídeos |
| `js.mutation_limit` | `10_000` | acima disso (mudanças no DOM num lote) o replay para. Páginas com gráficos grandes precisam de mais (o Farmer usa `50_000`) |
| `js.mutation_breadcrumb_limit` | `750` | a partir daí o replay registra um aviso de muitas mutações |
| `js.user_name_method` | `:name` | método de `@current_user` usado como nome |
| `js.user_email_method` | `:email` | idem para e-mail |
| `js.user_url_method` | `:user_url` | helper de rota para o link do usuário |
| `js.user_image_method` | `:avatar_image_url` | método da foto do usuário |

As taxas de replay aceitam lambdas, avaliadas a cada página. O Farmer usa isso
para ler o modo de replay do cadastro do projeto:

```ruby
config.js.replays_session_sample_rate = -> { MinhaConfig.taxa_de_sessoes }
```

Com as duas taxas de replay em `0`, o replay nem é carregado.

O SDK do navegador só é injetado quando o Haystack está ligado no ambiente
(`enabled_environments`), há DSN e o app tem asset pipeline.

## Deploy (Capistrano)

| Variável | Padrão |
|---|---|
| `:haystack_dsn` | `ENV['HAYSTACK_DSN']` |
| `:haystack_revision` | `current_revision` |
| `:haystack_user` | `$USER` |
| `:haystack_markers_url` | `<host da DSN>/api/requisicoes/markers` |

Fora do Capistrano: `Haystack::DeployMarker.notify(dsn:, revision:, user:)`.

## Exemplo completo (o do Farmer)

O Farmer é, ao mesmo tempo, o servidor do Haystack e um app monitorado por
ele. O initializer dele (`config/initializers/haystack.rb` no repositório do
Farmer) mostra as opções acima em uso, incluindo taxas de replay lidas do
banco e o `traces_sampler` que ignora as próprias rotas de API.
