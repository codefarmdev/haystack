# haystack-rails

Integração do Haystack 1.x com Rails (fork do [sentry-rails](https://github.com/getsentry/sentry-ruby/tree/master/sentry-rails)):
captura de erros de controllers, jobs e views, transações com params, sessão,
IP e memória, e o SDK do navegador (erros de JS e replay) injetado nas páginas
HTML.

Requer Rails 5.2+. O SDK do navegador precisa do asset pipeline (Sprockets).

A documentação está no [README do repositório](../README.md) e em [docs/](../docs),
especialmente [instalacao.md](../docs/instalacao.md) e [replay.md](../docs/replay.md).

```bash
RAILS_VERSION=6.1 bundle exec rspec
```
