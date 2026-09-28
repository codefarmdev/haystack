# Migração do Haystack 0.x para o 1.x

O 0.x (branch `master`) e o 1.x (branch `v1`) convivem: o Farmer continua
aceitando o endpoint antigo, então dá para migrar **um app de cada vez**.

## O que muda no app

| No 0.x | No 1.x |
|---|---|
| `gem 'haystack', git: '...', branch: :master` | bloco `git ..., branch: 'v1'` com `haystack` e `haystack-rails` ([instalacao.md](instalacao.md#2-gemfile)) |
| `config/haystack.yml` | `config/initializers/haystack.rb` (apague o yml) |
| `HAYSTACK_TOKEN` + `endpoint` | `HAYSTACK_DSN` (endereço + token num valor só) |
| `active: true` por ambiente | `config.enabled_environments = %w[production]` |
| `name:` | o nome do projeto no Farmer (não vai no app) |
| `slow_request_threshold:` | campo do projeto no Farmer (requisições acima dele guardam os detalhes) |
| `ignore_exceptions:` | `config.excluded_exceptions += [...]` |
| `ignore_actions:` | `config.before_send_transaction` (abaixo) |
| `Haystack.add_exception(e)` | continua funcionando (ou `Haystack.capture_exception(e)`) |
| `Haystack.send_exception(e, tags)` | continua funcionando |
| `require 'haystack/capistrano'` | igual; lê a `HAYSTACK_DSN` da máquina de deploy |
| `set :haystack_revision` / `:haystack_user` | iguais |

### `ignore_actions`

No 0.x, as ações listadas não mandavam nada, nem erros. No 1.x o equivalente
descarta só a medição de desempenho; **os erros dessas ações continuam
chegando**:

```ruby
IGNORADAS = %w[Api::V1::ExpoTokensController#create ActionMailer::DeliveryJob].freeze

Haystack.init do |config|
  # ...
  config.before_send_transaction = lambda do |event, _hint|
    IGNORADAS.include?(event.transaction) ? nil : event
  end
end
```

Nos jobs, o nome no 1.x é só a classe (`ActionMailer::DeliveryJob`, sem `#perform`).

### Recursos do 0.x que não existem no 1.x

Nenhum app da Codefarm usa: `Haystack.monitor_transaction`, `tag_request`,
`instrument`, métricas (`increment_counter`, `set_gauge`) e as integrações com
DelayedJob, Resque, Sinatra/Padrino por instrumentação própria. Sidekiq tem
a gem `haystack-sidekiq`; jobs via ActiveJob já são cobertos pelo
`haystack-rails`.

## O que muda no Farmer

Nada: o projeto é o mesmo e o token também. As agulhas novas chegam pelo
endpoint v2 e aparecem nas mesmas telas, com mais informação (stacktrace
com código, breadcrumbs, replay).

## Diferenças que o time vai notar

- **Mais envios:** o 0.x juntava um minuto de requisições num pacote só. O 1.x
  manda cada requisição, em segundo plano, sem deixar o site mais lento. Para
  reduzir, amostre as transações (`traces_sample_rate = 0.2`); erros são
  sempre 100%.
- **Erros do navegador e replay:** novos. Precisam do asset pipeline.
- **Memória por requisição:** só em Linux (lida de `/proc`), como nos servidores.

## Situação dos apps antigos (setembro/2026)

| App | Rails / Ruby | Turbolinks no JS | Erro de backend | Replay de erro de backend |
|---|---|---|---|---|
| imobeasy | 5.2 / 2.6 | não | `redirect_to server_error_url` | não (limitação) |
| nac-am | 5.2 / 2.6 | não | `redirect_to server_error_url` | não (limitação) |
| new-nac-am | 6.1 / 3.2 | sim | `render 'home/error'` | sim |
| old-new-nac-am | 6.1 / 3.0 | sim | `render 'home/error'` | sim |

Todos recebem erros de backend, transações, erros de JS e replay de erro de
JS. O Rails 5.2 com Ruby 2.6 é testado pela [suíte de integração](../integration/README.md).

## Passo a passo por app

1. Gemfile ([instalacao.md](instalacao.md#2-gemfile)) e `bundle install`.
2. Crie o initializer a partir do `config/haystack.yml` (tabela acima) e apague o yml.
3. Troque `HAYSTACK_TOKEN` por `HAYSTACK_DSN` no servidor **e** na máquina de deploy.
4. Opcional: adicione `Haystack.set_user` num `before_action` ([instalacao.md](instalacao.md#4-usuário-e-erros-tratados)).
5. Deploy e [verificação](instalacao.md#8-verifique).

Para voltar ao 0.x, reverta o Gemfile, o initializer e a variável: o Farmer
aceita os dois.
