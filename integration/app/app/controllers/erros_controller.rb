# Erros sem rescue_from: quem trata é o Rails (página 500 / JSON de erro)
class ErrosController < ApplicationController
  def nao_tratado
    raise ErroDeIntegracao, "Erro não tratado (#{marca})"
  end

  def ignorado
    raise ErroIgnorado, "Erro ignorado (#{marca})"
  end

  def job
    JobQueFalha.perform_later(marca)
    render plain: 'job enfileirado'
  end

  def api_ok
    respond_to do |format|
      format.json { render json: { ok: true, modo: modo } }
    end
  end

  def api_erro
    respond_to do |format|
      format.json { raise ErroDeIntegracao, "Erro na API (#{marca})" }
    end
  end
end
