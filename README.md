# Haystack

Monitoramento de erros, desempenho e sessões dos apps da Codefarm. Os apps
usam estas gems; os dados aparecem no **Farmer** (módulo Haystack), onde viram
**agulhas** (erros), **requisições** (desempenho) e **replays** (gravação da
tela do usuário até o erro).

O Haystack 1.0 é um fork do [sentry-ruby](https://github.com/getsentry/sentry-ruby)
5.22 com o SDK de navegador do Sentry 8.47, renomeados para Haystack e
ajustados para enviar ao Farmer.

> **Duas versões no mesmo repositório**
>
> | Branch | Versão | Quem usa |
> |---|---|---|
> | `master` | 0.x (gem antiga, baseada no AppSignal) | apps ainda não migrados |
> | `v1` | 1.x (esta) | apps novos e migrados |
>
> O `master` **não pode** receber o 1.x: os apps antigos instalam a gem direto
> do `master` e quebrariam no próximo deploy. Quando todos migrarem, a `v1`
> entra no `master`. Veja [docs/desenvolvimento.md](docs/desenvolvimento.md).

## Como funciona

```
 App Rails (gem haystack + haystack-rails)                 Farmer
┌────────────────────────────────────────────┐        ┌──────────────────────────┐
│ backend: erros, transações, deploy         │──────▶ │ POST /api/v2/requests/   │
│                                            │ HTTP   │   api/:token/envelope    │
│ página HTML ◀─ injector (SDK do navegador) │        │                          │
│   navegador: erros de JS, carregamento     │──────▶ │ agulhas, requisições,    │
│   de páginas e replay da sessão            │        │ replays                  │
└────────────────────────────────────────────┘        └──────────────────────────┘
```

- **Backend:** erros não tratados são capturados por um middleware; erros
  tratados em `rescue_from` são enviados com `Haystack.capture_exception`
  (ou `Haystack.add_exception`, a chamada do 0.x). Cada requisição vira uma
  transação com os tempos de banco e view, params e sessão filtrados, IP e
  memória.
- **Navegador:** o `haystack-rails` injeta o SDK em toda página HTML. Ele envia
  erros de JS, o tempo de carregamento e, quando há erro, o **replay** do
  último minuto ou dois antes dele, inclusive quando o erro foi no backend
  (em apps com Turbolinks). Veja [docs/replay.md](docs/replay.md).
- **Deploy:** a task `haystack:deploy` do Capistrano registra cada deploy.

Tudo vai para o Farmer pela **DSN** do projeto:

```
https://haystack@farmer.codefarm.com.br/api/v2/requests/TOKEN_DO_PROJETO
```

## Instalação rápida

```ruby
# Gemfile
git 'https://github.com/codefarmdev/haystack.git', branch: 'v1' do
  gem 'haystack', '~> 1.0'
  gem 'haystack-rails', '~> 1.0'
end
```

```ruby
# config/initializers/haystack.rb
Haystack.init do |config|
  config.dsn = ENV['HAYSTACK_DSN']
  config.enabled_environments = %w[production]
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.traces_sample_rate = 1.0
end
```

```bash
# no servidor (e na máquina que faz o deploy)
HAYSTACK_DSN=https://haystack@farmer.codefarm.com.br/api/v2/requests/TOKEN_DO_PROJETO
```

O passo a passo completo, com usuário, erros tratados, deploy e verificação,
está em [docs/instalacao.md](docs/instalacao.md).

## Documentação

| | |
|---|---|
| [Instalação num projeto](docs/instalacao.md) | passo a passo e checklist |
| [Migração do Haystack 0.x](docs/migracao-0x.md) | o que muda nos apps antigos |
| [Configuração](docs/configuracao.md) | todas as opções que usamos |
| [Replay](docs/replay.md) | como funciona, requisitos e limitações |
| [Desenvolvimento da gem](docs/desenvolvimento.md) | estrutura, publicação na `v1`, o bundle JS |
| [Testes](docs/testes.md) | as camadas de teste e como rodar cada uma |
| [Suíte de integração](integration/README.md) | apps de verdade em Docker, com navegador |

## Compatibilidade

| | |
|---|---|
| Ruby | 2.4+ (testado em 2.6, 3.0 e 3.2) |
| Rails | 5.2+ (testado em 5.2 e 6.1) |
| SDK do navegador e replay | só em apps com asset pipeline (Sprockets) |
| Replay de erro de backend | só em apps com Turbolinks (ou Turbo) |
| Sidekiq | gem `haystack-sidekiq` (opcional) |

## Gems

| Gem | Pasta | O que faz |
|---|---|---|
| `haystack` | [haystack/](haystack) | núcleo: captura, transações, envio, `haystack/capistrano` |
| `haystack-rails` | [haystack-rails/](haystack-rails) | integração com Rails e o SDK do navegador |
| `haystack-sidekiq` | [haystack-sidekiq/](haystack-sidekiq) | erros e transações dos jobs do Sidekiq |

## Licença

MIT, como o sentry-ruby original ([LICENSE](LICENSE)).
