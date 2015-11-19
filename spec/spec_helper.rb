ENV['RAILS_ENV'] ||= 'test'
require 'rspec'
require 'pry'
require 'timecop'
require 'webmock/rspec'

puts "Runnings specs in #{RUBY_VERSION} on #{RUBY_PLATFORM}"

begin
  require 'rails'
  Dir[File.expand_path(File.join(File.dirname(__FILE__), 'support/rails','*.rb'))].each {|f| require f}
  puts 'Rails present, running Rails specific specs'
  RAILS_PRESENT = true
rescue LoadError
  puts 'Rails not present, skipping Rails specific specs'
  RAILS_PRESENT = false
end

def rails_present?
  RAILS_PRESENT
end

def active_record_present?
  require 'active_record'
  true
rescue LoadError
  false
end

def running_jruby?
  defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
end

def capistrano_present?
  !! Gem.loaded_specs['capistrano']
end

def capistrano2_present?
  capistrano_present? &&
    Gem.loaded_specs['capistrano'].version < Gem::Version.new('3.0')
end

def capistrano3_present?
  capistrano_present? &&
    Gem.loaded_specs['capistrano'].version >= Gem::Version.new('3.0')
end

def sequel_present?
  require 'sequel'
  true
rescue LoadError
  false
end

def padrino_present?
  require 'padrino'
  true
rescue LoadError
  false
end

require 'haystack'

Dir[File.expand_path(File.join(File.dirname(__FILE__), 'support/helpers','*.rb'))].each {|f| require f}

def tmp_dir
  @tmp_dir ||= File.expand_path(File.join(File.dirname(__FILE__), 'tmp'))
end

def fixtures_dir
  @fixtures_dir ||= File.expand_path(File.join(File.dirname(__FILE__), 'support/fixtures'))
end

RSpec.configure do |config|
  config.include ConfigHelpers
  config.include NotificationHelpers
  config.include TransactionHelpers

  config.before do
    ENV['PWD'] = File.expand_path(File.join(File.dirname(__FILE__), '../'))
    ENV['RAILS_ENV'] = 'test'
    ENV.delete('HAYSTACK_PUSH_API_KEY')
    ENV.delete('HAYSTACK_API_KEY')
  end

  config.after do
    FileUtils.rm_f(File.join(project_fixture_path, 'log/haystack.log'))
    Haystack.logger = nil
  end
end

class VerySpecificError < RuntimeError
end
