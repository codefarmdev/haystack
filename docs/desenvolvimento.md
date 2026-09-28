# Desenvolvimento da gem

## Estrutura

```
haystack/            núcleo (fork do sentry-ruby 5.22)
  lib/haystack.rb              API pública: init, capture_exception, add_exception...
  lib/haystack/deploy_marker.rb  marcador de deploy
  lib/haystack/integrations/capistrano/haystack.cap
haystack-rails/      integração com Rails (fork do sentry-rails)
  lib/haystack/rails/middleware/injector.rb   injeta o SDK do navegador
  lib/haystack/rails/controller_transaction.rb  params, sessão, IP, memória
  app/assets/javascripts/haystack/bundle.tracing.replay.min.js   SDK do navegador
haystack-sidekiq/    integração com Sidekiq
integration/         suíte de integração (apps Rails em Docker + navegador)
docs/                esta documentação
```

### O que difere do sentry-ruby

- Tudo renomeado: `Sentry` → `Haystack`, headers `sentry-trace` →
  `haystack-trace`, `window.Sentry` → `window.Haystack`, atributos
  `data-sentry-*` → `data-haystack-*`.
- `Haystack.add_exception` / `send_exception` (API do 0.x).
- `capture_exception` durante uma requisição marca o `env` com o id do evento
  (`haystack.error_event_id`), para o injector devolver o header
  `X-Haystack-Event-Id`.
- `haystack-rails`: o injector do SDK do navegador; params, sessão, IP,
  memória e `view_runtime` em erros e transações; engine sem
  `isolate_namespace` (o Farmer tem controllers `Haystack::*`).
- `config.js` (`JsConfig`) com as opções do navegador.
- `Haystack::DeployMarker` e a task do Capistrano, que enviam ao endpoint de
  marcadores do Farmer.
- A integração com GraphQL não funciona (a gem graphql só traz o tracer do
  Sentry).

## Desenvolvendo junto com o Farmer

O Farmer instala a gem da branch `v1`. Para testar uma mudança local sem
publicar:

```bash
# no Farmer
bundle config set --local local.haystack ~/Developer/haystack
bundle install
```

O Bundler passa a usar a pasta local (que precisa estar na branch `v1`).
Cuidado: o `Gemfile.lock` passa a apontar para o commit local; publique a `v1`
antes de commitar o lock. Para voltar:

```bash
bundle config unset --local local.haystack
bundle install
```

## Rodando os testes

Resumo (detalhes em [testes.md](testes.md)):

```bash
cd haystack && bundle exec rspec && bundle exec rake isolated_specs
cd haystack-rails && RAILS_VERSION=6.1 bundle exec rspec
integration/bin/rodar
```

## Publicando uma versão

A branch `v1` é a publicação: os apps instalam direto dela.

1. Rode os testes (acima) e a suíte de integração.
2. Atualize a versão em `haystack/lib/haystack/version.rb`,
   `haystack-rails/lib/haystack/rails/version.rb` e
   `haystack-sidekiq/lib/haystack/sidekiq/version.rb`, e o `CHANGELOG.md`.
   Versionamento semântico: correção = patch, recurso novo = minor, algo que
   exige mudar os apps = major (aí os apps precisam de outra branch, ex.: `v2`).
3. `git push origin v1`.
4. Em cada app: `bundle update haystack haystack-rails` e deploy.

### Proteção do `master`

O `master` tem o Haystack 0.x, que os apps antigos instalam direto dele. Um
push do 1.x lá quebra o próximo deploy de todos eles. Na máquina do Pedro há
um hook local (`.git/hooks/pre-push`) que bloqueia push para `master`/`main` do
`codefarmdev/haystack`, remoção da `v1` e `push --force` na `v1`. O ideal é
também ativar a proteção do `master` no GitHub (Settings > Branches).

Quando todos os apps estiverem no 1.x: merge da `v1` no `master` (é
fast-forward: a `v1` descende do `master`) e troca de `branch: 'v1'` nos apps.

## O bundle do SDK do navegador

`haystack-rails/app/assets/javascripts/haystack/bundle.tracing.replay.min.js` é
o bundle CDN do Sentry JavaScript **8.47.0** (`bundle.tracing.replay.min.js`)
com estas alterações:

1. **Renomeação:** `Sentry` → `Haystack` (global `window.Haystack`,
   `__HAYSTACK__`, `haystack-trace`, `data-haystack-*`, `haystack-block` etc.).
2. **Project id completo:** o SDK original cortava o último segmento da DSN
   para só os dígitos iniciais (`/^\d+/`). O token do Farmer é hexadecimal, então
   o corte foi removido.
3. **Buffer de 60 a 120 s** (commit `8f2b705b`): no modo buffer, a cada
   checkout (60 s) o SDK original fazia `eventBuffer.clear()`. O bundle chama
   `trimToPreviousCheckout()`, um método novo do `EventBufferArray` que descarta
   só os eventos anteriores ao checkout anterior. Funciona só com o buffer
   síncrono, por isso o injector passa `useCompression: false`.

Para atualizar o SDK para outra versão, baixe o bundle novo do CDN do Sentry e
reaplique as três alterações (procure por `eventBuffer.clear`/`hasCheckout` e
pela regex `/^\d+/` no parse da DSN), depois rode a suíte de integração, que
verifica replay de JS e de backend num navegador de verdade.
