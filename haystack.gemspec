# -*- encoding: utf-8 -*-
require File.expand_path('../lib/haystack/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = [
    'José Morais',
    'Robert Beekman',
    'Steven Weller',
    'Thijs Cadier',
    'Ron Cadier',
    'Jacob Vosmaer'
  ]
  gem.email                 = ['jmorais@codefarm.com.br']
  gem.description           = 'Gem do Haystack - Code Farm'
  gem.summary               = 'Logs de performance e exceptions para o Farmer'
  gem.homepage              = 'https://github.com/codefarmdev/haystack'
  gem.license               = 'MIT'

  gem.files                 = `git ls-files`.split($\)
  gem.executables           = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files            = gem.files.grep(%r{^(test|spec|features)/})
  gem.name                  = 'haystack'
  gem.require_paths         = ['lib']
  gem.version               = Haystack::VERSION
  gem.required_ruby_version = '>= 1.9'

  gem.add_dependency 'rack'
  gem.add_dependency 'thread_safe'
  gem.add_dependency 'get_process_mem'

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec', '~> 2.14.1'
  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'timecop'
  gem.add_development_dependency 'webmock'

  if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'rbx'
    gem.add_development_dependency 'racc'
    gem.add_development_dependency 'rubysl-enumerator'
    gem.add_development_dependency 'rubysl-net-http'
    gem.add_development_dependency 'rubysl-rexml'
    gem.add_development_dependency 'rubysl-test-unit'
  end
end
