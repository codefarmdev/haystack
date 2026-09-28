# haystack-sidekiq

Integração do Haystack 1.x com o Sidekiq (fork do sentry-sidekiq): erros e
transações dos jobs. Só é necessária para jobs do Sidekiq escritos sem
ActiveJob; os jobs ActiveJob já são cobertos pelo `haystack-rails`.

```ruby
git 'https://github.com/codefarmdev/haystack.git', branch: 'v1' do
  gem 'haystack', '~> 1.0'
  gem 'haystack-rails', '~> 1.0'
  gem 'haystack-sidekiq', '~> 1.0'
end
```

A documentação está no [README do repositório](../README.md).
