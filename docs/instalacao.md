# Instalação num projeto

Passo a passo para colocar o Haystack 1.x num app Rails. Para um app que já
usa a gem 0.x, leia também [migracao-0x.md](migracao-0x.md).

## 1. Cadastre o projeto no Farmer

No Farmer, **Haystack > Projetos > Novo**. O projeto ganha um **token**. A
DSN do app é:

```
https://haystack@farmer.codefarm.com.br/api/v2/requests/TOKEN_DO_PROJETO
```

- `https://farmer.codefarm.com.br` é o Farmer de produção (em desenvolvimento,
  o endereço local, ex.: `http://haystack@new-farmer.codefarm.com.br.test/...`).
- `haystack@` é fixo (o formato exige um nome ali; o Farmer ignora).
- `TOKEN_DO_PROJETO` diz de qual projeto são os dados.

Ainda no cadastro, escolha o **modo de replay**: *Desligado*, *Só com erro*
(padrão) ou *Com erro e % das sessões*.

## 2. Gemfile

```ruby
git 'https://github.com/codefarmdev/haystack.git', branch: 'v1' do
  gem 'haystack', '~> 1.0'
  gem 'haystack-rails', '~> 1.0'
  # gem 'haystack-sidekiq', '~> 1.0'   # só se o app usa Sidekiq direto (sem ActiveJob)
end
```

Sempre `branch: 'v1'`. Sem ela o Bundler pega o `master`, que é o Haystack 0.x.

```bash
bundle install
```

## 3. Initializer

`config/initializers/haystack.rb`:

```ruby
Haystack.init do |config|
  config.dsn = ENV['HAYSTACK_DSN']

  # Só envia em produção (em development, se quiser testar, inclua 'development')
  config.enabled_environments = %w[production]

  # Rastro (breadcrumbs) das queries, views e chamadas HTTP antes do erro
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Desempenho: 1.0 = toda requisição vira uma transação no Farmer
  config.traces_sampler = lambda do |sampling_context|
    path = sampling_context.dig(:env, 'PATH_INFO').to_s
    next 0.0 if path.start_with?('/assets', '/cable', '/health', '/favicon')

    1.0
  end

  # Exceções que não interessam (o antigo ignore_exceptions do haystack.yml)
  config.excluded_exceptions += %w[ActionController::InvalidAuthenticityToken]
end
```

Todas as opções estão em [configuracao.md](configuracao.md).

## 4. Usuário e erros tratados

No `ApplicationController`:

```ruby
class ApplicationController < ActionController::Base
  before_action :set_haystack_user
  rescue_from Exception, with: :render_error

  private

  def set_haystack_user
    return unless current_user

    Haystack.set_user(id: current_user.id, email: current_user.email, username: current_user.name)
  end

  def render_error(exception)
    Haystack.capture_exception(exception)   # ou Haystack.add_exception (API do 0.x)
    render 'home/error', layout: 'error', status: 500
  end
end
```

- Erros **não tratados** são capturados sozinhos. Os tratados em `rescue_from`
  precisam da chamada acima, senão o Farmer não fica sabendo.
- A captura dentro de uma requisição também avisa o navegador (header
  `X-Haystack-Event-Id`), que envia o replay do erro. Veja [replay.md](replay.md).
- `Haystack.set_user` vale para os erros do backend. No navegador, o usuário
  vem de `@current_user` do controller (métodos configuráveis em
  `config.js.user_*_method`).
- Por padrão o Haystack já ignora `ActiveRecord::RecordNotFound`,
  `ActionController::RoutingError` e outros erros de "página não existe"
  (lista em `haystack-rails/lib/haystack/rails/configuration.rb`).

Outros usos:

```ruby
Haystack.capture_message('Importação terminou sem registros', level: :warning)

Haystack.with_scope do |scope|
  scope.set_tags(area: 'financeiro')
  scope.set_extras(pedido_id: pedido.id)
  Haystack.capture_exception(e)
end
```

## 5. Página de erro e Turbolinks (para o replay de erro de backend)

O replay de um erro de backend só funciona se:

1. o app usa **Turbolinks** (ou Turbo) no JavaScript (`//= require turbolinks`
   no `application.js`, não basta a gem no Gemfile);
2. o erro é **renderizado** (`render ... status: 500`), não redirecionado; e
3. o layout de erro carrega os **mesmos** assets rastreados do layout normal
   (`data-turbolinks-track: 'reload'`). Se forem diferentes, o Turbolinks
   recarrega a página inteira e o replay se perde.

Sem isso, o erro chega normalmente no Farmer, só sem replay. Detalhes em
[replay.md](replay.md).

## 6. Deploy (Capistrano)

No `config/deploy.rb`:

```ruby
set :haystack_revision, `git log --pretty=format:'%h' -n 1`.chomp   # opcional
set :haystack_user, ENV['GITHUB_USER']                              # opcional
require 'haystack/capistrano'
```

Só o `require` já registra a task `haystack:deploy` para rodar depois de
`deploy:finished`, como no Haystack 0.x. Para rodar em outro momento, declare o
hook (ex.: `before 'puma:restart', 'haystack:deploy'`); ela roda uma vez só.

A task lê a `HAYSTACK_DSN` **da máquina que roda o deploy** (ou
`set :haystack_dsn, '...'`) e registra revisão e usuário. Se falhar, só avisa:
o deploy continua.

Opções: `:haystack_dsn`, `:haystack_revision` (padrão: `current_revision`),
`:haystack_user` (padrão: `$USER`), `:haystack_markers_url`.

## 7. Variável de ambiente

No servidor (`.env`, systemd, o que o app usar):

```bash
HAYSTACK_DSN=https://haystack@farmer.codefarm.com.br/api/v2/requests/TOKEN_DO_PROJETO
```

## 8. Verifique

Depois do deploy:

1. Abra uma página do app: em **Haystack > Projetos > (projeto) > Requisições**
   aparecem a requisição do backend (`Controller#action`) e a do navegador
   (a URL da página).
2. No console do navegador, `window.Haystack` existe e
   `Haystack.getClient().getDsn()` mostra a DSN.
3. Gere um erro de teste (ex.: no console Rails de produção,
   `Haystack.capture_exception(RuntimeError.new('teste do Haystack'))`) e veja a
   agulha em **Agulhas**.
4. No Farmer, `bin/rails haystack:verificar TOKEN=...` testa o recebimento
   ponta a ponta (veja a documentação do Haystack no Farmer).

Se nada aparece, veja [Problemas comuns](#problemas-comuns).

## Checklist

- [ ] Projeto cadastrado no Farmer, com o modo de replay escolhido
- [ ] Gemfile com `branch: 'v1'`, `bundle install` e `Gemfile.lock` commitado
- [ ] `config/initializers/haystack.rb`
- [ ] `Haystack.set_user` e `Haystack.capture_exception` nos `rescue_from`
- [ ] Layout de erro com os mesmos assets rastreados (se tiver Turbolinks)
- [ ] `require 'haystack/capistrano'` no `deploy.rb`
- [ ] `HAYSTACK_DSN` no servidor e na máquina de deploy
- [ ] Requisição, erro de teste e deploy aparecendo no Farmer

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| Nada chega no Farmer | `HAYSTACK_DSN` ausente no servidor, ambiente fora de `enabled_environments` ou token errado (o Farmer responde 404; veja o log do app com `config.debug = true`) |
| Erros do backend chegam, os do navegador não | O app não tem asset pipeline (Sprockets), ou o bundle não foi precompilado (`/assets/haystack/bundle.tracing.replay.min-*.js` dá 404) |
| Erro tratado em `rescue_from` não chega | Falta `Haystack.capture_exception` (ou a exceção está em `excluded_exceptions`) |
| Erro de backend sem replay | Ver o passo 5 (Turbolinks, render, layout) |
| Replay com poucos segundos antes do erro | O buffer do navegador passou de 20 MB (páginas com muitas mutações, ex.: gráficos ou o próprio player de replay). Marque essas áreas com `data-haystack-block` |
| `bundle install` instala a 0.x | Falta `branch: 'v1'` no Gemfile |
