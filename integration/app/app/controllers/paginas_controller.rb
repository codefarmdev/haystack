class PaginasController < ApplicationController
  def index
  end

  def pagina2
  end

  def formulario
  end

  # POST com password/cartao: os valores nunca podem sair do servidor
  def enviar
    @nome = params[:nome]
  end

  # Destino do redirect do ErrosRedirectController (como o server_error do
  # projeto Rails 5.2)
  def erro_servidor
    render 'paginas/erro', status: 500
  end
end
