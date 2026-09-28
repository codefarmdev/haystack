ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup'
# Rails < 7.1 com concurrent-ruby >= 1.3.5 depende de Logger já carregado
require 'logger'
