Monitor do Haystack
=================

Essa gem coleta informações de erro e performance da aplicação em Rails e envia
para o [Farmer](http://farmer.codefarm.com.br).

## Middleware de pós-processamento

Haystack envia eventos
[ActiveSupport::Notification](http://api.rubyonrails.org/classes/ActiveSupport/Notifications.html) para
o Farmer.

Esses eventos contém metadados básicos como nome do evento e a timestamp, além de
um 'payload' de informações de log. Haystack usa uma stack de middleware de pós-processamenot
para fazer uma limpeza nos eventos antes de eles serem enviados para o Farmer. Você
pode adiciona seu próprio middleware nessa stack em `config/environment/my_env.rb`.

### Exemplos

#### Template básico

```ruby
class MiddlewareTemplate
  def call(event)
    # modify the event in place
    yield # pass control to the next middleware
    # modify the event some more
  end
end

Haystack.post_processing_middleware.add MiddlewareTemplate
```

#### Remover payloads inúteis

```ruby
class RemoveBoringPayload
  def call(event)
    event.payload.clear unless event.name == 'interesting'
    yield
  end
end
```

## Desenvolvimento

Execute `rake bundle` ou execute `bundle install` para todos os Gemfiles:

```
bundle --gemfile gemfiles/capistrano2.gemfile
bundle --gemfile gemfiles/capistrano3.gemfile
bundle --gemfile gemfiles/no_dependencies.gemfile
bundle --gemfile gemfiles/rails-3.0.gemfile
bundle --gemfile gemfiles/rails-3.1.gemfile
bundle --gemfile gemfiles/rails-3.2.gemfile
bundle --gemfile gemfiles/rails-4.0.gemfile
bundle --gemfile gemfiles/rails-4.1.gemfile
bundle --gemfile gemfiles/rails-4.2.gemfile
bundle --gemfile gemfiles/sinatra.gemfile
```

Para executar as specs com alguma Gemfile específica:

```
BUNDLE_GEMFILE=gemfiles/capistrano2.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/capistrano3.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/no_dependencies.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-3.0.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-3.1.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-3.2.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-4.0.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-4.1.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rails-4.2.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/sinatra.gemfile bundle exec rspec
```

Ou execute `rake generate_bundle_and_spec_all` para gerar um script que execute
as specs para todas as combinações de Ruby e gems que suportamos. Você precisa
do RVM ou Rbenv para fazer isso. Travis executará essas specs também.

Créditos
-------

![codefarm](https://codefarm.com.br/img/logo2.png)

Haystack é mantido por [Code Farm](https://codefarm.com.br/). Baseada no agent
da [AppSignal](https://appsignal.com).