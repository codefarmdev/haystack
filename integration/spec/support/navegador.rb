# frozen_string_literal: true

require "selenium-webdriver"

# Chrome remoto (container chrome) via Selenium. O navegador acessa o app como
# http://app:3000 e manda os envelopes para http://receiver:9292, como o app.
module AjudaNavegador
  SELENIUM_URL = ENV.fetch("SELENIUM_URL", "http://chrome:4444")

  def navegador
    @navegador ||= begin
      opcoes = Selenium::WebDriver::Chrome::Options.new
      opcoes.add_argument("--headless=new")
      opcoes.add_argument("--no-sandbox")
      opcoes.add_argument("--disable-dev-shm-usage")
      opcoes.add_argument("--window-size=1280,900")
      # http://app:3000 não é localhost: sem isso o Chrome tenta https antes
      opcoes.add_argument("--disable-features=HttpsUpgrades,HttpsFirstBalancedModeAutoEnable")
      Selenium::WebDriver.for(:remote, url: SELENIUM_URL, options: opcoes)
    end
  end

  def navegador_aberto?
    !@navegador.nil?
  end

  def fechar_navegador
    @navegador&.quit
  rescue StandardError
    nil
  ensure
    @navegador = nil
  end

  def visitar(caminho)
    navegador.navigate.to(url_do_app(caminho))
    esperar_pagina_pronta
  end

  def esperar_pagina_pronta(timeout: 15)
    esperar_ate("document.readyState complete", timeout: timeout, intervalo: 0.1) do
      navegador.execute_script("return document.readyState") == "complete"
    end
  end

  def elemento(css)
    navegador.find_element(css: css)
  end

  def clicar(css)
    elemento(css).click
  end

  def digitar(css, texto)
    elemento(css).send_keys(texto)
  end

  def js(script, *args)
    navegador.execute_script(script, *args)
  end

  def titulo_da_pagina
    elemento("#titulo").text
  rescue Selenium::WebDriver::Error::NoSuchElementError, Selenium::WebDriver::Error::StaleElementReferenceError
    ""
  end

  def esperar_titulo(trecho, timeout: 15)
    esperar_ate("página com título contendo #{trecho.inspect} (atual: #{titulo_da_pagina.inspect})", timeout: timeout, intervalo: 0.1) do
      titulo_da_pagina.include?(trecho)
    end
  end

  # Login falso: o cookie só pode ser criado com o navegador no domínio do app
  def entrar_como(id)
    visitar("/saude")
    navegador.manage.add_cookie(name: "usuario", value: id.to_s, path: "/")
  end

  def agora_ms
    (Time.now.to_f * 1000).to_i
  end
end
