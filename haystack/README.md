# haystack

Núcleo do Haystack 1.x (fork do [sentry-ruby](https://github.com/getsentry/sentry-ruby)
5.22): captura de erros e transações, envio ao Farmer, `Haystack::DeployMarker`
e `haystack/capistrano`.

Em apps Rails, use junto com o [`haystack-rails`](../haystack-rails). A
documentação está no [README do repositório](../README.md) e em [docs/](../docs).

```bash
bundle exec rspec                  # testes
bundle exec rake isolated_specs    # testes que precisam de processo próprio (Puma etc.)
```
