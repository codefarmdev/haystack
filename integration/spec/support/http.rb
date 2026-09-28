# frozen_string_literal: true

require "net/http"
require "uri"
require "cgi"

# Requisições HTTP diretas ao app (sem navegador; não segue redirects)
module AjudaHttp
  APP_URL = ENV.fetch("APP_URL", "http://aplicacao:3000").chomp("/")

  def url_do_app(caminho)
    "#{APP_URL}#{caminho}"
  end

  def http_get(caminho, cookies: {}, headers: {})
    requisicao = Net::HTTP::Get.new(caminho)
    preparar(requisicao, cookies, headers)
    executar(requisicao)
  end

  def http_post_form(caminho, dados, cookies: {}, headers: {})
    requisicao = Net::HTTP::Post.new(caminho)
    requisicao.set_form_data(dados)
    preparar(requisicao, cookies, headers)
    executar(requisicao)
  end

  # Cookies do Set-Cookie de uma resposta, como hash nome => valor
  def cookies_da_resposta(resposta)
    Array(resposta.get_fields("Set-Cookie")).each_with_object({}) do |linha, h|
      nome, valor = linha.split(";").first.split("=", 2)
      h[nome] = valor
    end
  end

  def token_csrf(html)
    html[/name="authenticity_token" value="([^"]+)"/, 1] || raise("authenticity_token não encontrado")
  end

  private

  def preparar(requisicao, cookies, headers)
    requisicao["Cookie"] = cookies.map { |k, v| "#{k}=#{v}" }.join("; ") unless cookies.empty?
    headers.each { |k, v| requisicao[k] = v }
  end

  def executar(requisicao)
    uri = URI(APP_URL)
    resposta = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 30) { |http| http.request(requisicao) }
    # O Net::HTTP devolve o corpo como binário; as páginas são UTF-8
    resposta.body&.force_encoding(Encoding::UTF_8)
    resposta
  end
end
