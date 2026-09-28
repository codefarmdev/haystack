# Testes

O Haystack tem três pontos que podem quebrar: a **gem**, a **integração da
gem com um app** (Rails, assets, Turbolinks, navegador) e o **Farmer** (o que
ele faz com o que recebe). Cada camada abaixo cobre um deles.

```
 1. Unitários da gem          haystack/, haystack-rails/          segundos
 2. Integração com apps       integration/ (Docker + Chrome)      minutos
 3. Contrato com o Farmer     no repositório do Farmer            segundos
 4. Verificação no ambiente   bin/rails haystack:verificar        no servidor
```

| Camada | Pega problemas como |
|---|---|
| 1. Unitários | uma opção que parou de funcionar, o header de erro que não é devolvido, params ou sessão sem filtro, XSS no script injetado, boot quebrando em app sem Sprockets, marcador de deploy |
| 2. Integração | a gem não instala ou não sobe numa versão de Ruby/Rails, o bundle JS não é precompilado, o SDK não carrega no navegador, erro de JS ou de backend que não chega, replay que não é enviado ou fica sem o erro |
| 3. Contrato | o Farmer grava um campo errado, deixa de ligar agulha, requisição e replay, perde o envelope por causa de acento ou gzip, grava um valor filtrado |
| 4. Verificação | DSN ou token errados, rota, proxy ou firewall bloqueando, migrations faltando no servidor |

## Quando rodar

| Mudança | Camadas |
|---|---|
| Código da gem (antes de `git push origin v1`) | 1 e 2 |
| Atualização do SDK do navegador (o bundle JS) | 2 (é a única que roda o navegador) |
| Recebimento no Farmer (`HaystackV2::*`, modelos) | 3 |
| Deploy do Farmer ou migração de um app | 4 |

## 1. Unitários da gem

```bash
bin/testes-unitarios                  # Ruby da máquina, haystack-rails com Rails 6.1
bin/testes-unitarios --ruby 2.6.4     # em Docker, Ruby 2.6 + Rails 5.2 (os apps mais antigos)
bin/testes-unitarios --rails 7.1      # outra versão do Rails
```

Ou direto:

```bash
cd haystack
bundle exec rspec                   # ~1100 exemplos
bundle exec rake isolated_specs     # Puma e outros que precisam de processo próprio

cd ../haystack-rails
RAILS_VERSION=6.1 bundle exec rspec # ~190 exemplos
```

Resultado em 28/09/2026: tudo verde no Ruby 3.2 (Rails 6.1) e no Ruby 2.6.4
(Rails 5.2). No Docker falham, por falta do ambiente e não da gem: os de
Redis (sem servidor Redis), o de release pelo git (sem `.git`) e, às vezes, o
de erro de conexão em `client/event_sending_spec.rb` (a mensagem depende da
rede do container). O do profiler falha no Ruby 2.6 (o profiler não é usado
pelos apps).

Vêm do sentry-ruby (ajustados para o Haystack), mais os específicos do Haystack:

| Arquivo | Cobre |
|---|---|
| `haystack-rails/spec/haystack/rails/middleware/injector_spec.rb` | injeção do SDK (onde, quando não), header `X-Haystack-Event-Id`, taxas de replay (inclusive lambdas), DSN do navegador, params/sessão/usuário/flash no script, proteção contra XSS, app sem Sprockets |
| `haystack-rails/spec/haystack/rails/request_context_spec.rb` | `rescue_from` + `Haystack.add_exception`; params, sessão, IP e memória nos erros e transações; nada filtrado vaza; filtro no Rails 5.2 |
| `haystack/spec/haystack/deploy_marker_spec.rb` | marcador de deploy contra um servidor HTTP de verdade e a task `haystack:deploy` com o DSL do Capistrano |
| `haystack/spec/haystack_spec.rb` (`.capture_exception`) | `add_exception`/`send_exception` do 0.x |
| `haystack/spec/haystack/rack/capture_exceptions_spec.rb` | erro tratado dentro da requisição marca a resposta |
| `haystack/spec/haystack/configuration_spec.rb` (`#js`) | padrões do `config.js` e independência do Rails |

Pendentes de propósito: GraphQL (integração não suportada) e os que exigem
Rails 7 (`ErrorReporter`).

## 2. Integração com apps (Docker)

```bash
integration/bin/rodar              # matriz padrão
integration/bin/rodar --so 2.6     # só uma entrada
```

Sobe, para cada versão de Ruby/Rails da matriz, um app Rails de verdade em
modo produção (assets precompilados), um **Farmer falso** que recebe e
decodifica os envelopes, e um **Chrome** controlado por Selenium. Os testes
navegam pelo app e conferem o que chegou. Detalhes, cenários e como
acrescentar versões: [integration/README.md](../integration/README.md).

A matriz reproduz os apps da Codefarm: Ruby 2.6 + Rails 5.2 (imobeasy,
nac-am), Ruby 3.0 e 3.2 + Rails 6.1 (Farmer, new-nac-am).

## 3. Contrato com o Farmer

No repositório do Farmer (ver `docs/HAYSTACK.md` lá):

```bash
bundle exec rspec spec/requests/api/v2 spec/services/haystack_v2
```

Dois tipos de envelope entram nesses testes:

- **Gravados:** capturados de uma execução real da gem e do SDK do navegador
  (`spec/fixtures/haystack/envelopes/`). Cobrem principalmente o navegador e o
  replay, que só um navegador gera.
- **Gerados na hora** pela gem instalada no Farmer: quando a gem muda o formato,
  esses testes acompanham sozinhos depois do `bundle update haystack`.

Para regenerar os gravados, rode a camada 2 com `--fixtures <pasta>` e copie os
arquivos para o Farmer.

## 4. Verificação no ambiente

Depois de um deploy do Farmer ou da migração de um app, no servidor do Farmer:

```bash
bin/rails haystack:verificar                 # projeto da HAYSTACK_DSN do Farmer
bin/rails haystack:verificar TOKEN=<token>   # outro projeto
```

Envia um erro e uma transação de teste pela gem, espera os dois no banco,
confere a ligação entre eles e apaga os registros.
