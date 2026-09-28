# frozen_string_literal: true

require "securerandom"
require "time"

Dir[File.join(__dir__, "support", "*.rb")].sort.each { |arquivo| require arquivo }

# Informações da entrada da matriz (vindas do bin/rodar)
module Matriz
  module_function

  def rails
    Gem::Version.new(ENV.fetch("RAILS_VERSION_APP", "6.1.7.10"))
  end

  def ruby
    ENV.fetch("RUBY_VERSION_APP", "?")
  end

  def rails_antes_de?(versao)
    rails < Gem::Version.new(versao)
  end

  # Tempo (s) que o replay continua gravando depois de um erro
  # Valor efetivo: o injector grava pelo menos 6 s depois do erro
  def replay_apos_erro
    [Integer(ENV.fetch("HAYSTACK_REPLAY_AFTER_ERROR_SECONDS", "7")), 6].max
  end
end

module AjudaGeral
  # Identificador único do teste: vai na URL e acaba na mensagem do erro
  def nova_marca
    "m#{SecureRandom.hex(6)}"
  end
end

RSpec.configure do |config|
  config.include AjudaGeral
  config.include AjudaReceptor
  config.include AjudaHttp
  config.include AjudaNavegador

  config.expect_with(:rspec) { |c| c.max_formatted_output_length = 2000 }
  config.order = :defined

  config.before(:suite) do
    ajuda = Object.new.extend(AjudaReceptor, AjudaHttp)
    ajuda.esperar_ate("receptor no ar", timeout: 60) { ajuda.receptor.saudavel? }
    ajuda.esperar_ate("app no ar", timeout: 120) do
      ajuda.http_get("/saude").code == "200"
    rescue StandardError
      false
    end
    puts "Entrada: Ruby #{Matriz.ruby} / Rails #{Matriz.rails} (replay para #{Matriz.replay_apos_erro}s após o erro)"
  end

  # Cada exemplo começa com o receptor vazio e um navegador novo (sessionStorage
  # limpo, sem replay em andamento)
  config.before(:each) { receptor.limpar }
  config.after(:each) { fechar_navegador }
end
