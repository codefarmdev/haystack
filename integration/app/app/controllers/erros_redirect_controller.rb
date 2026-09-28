# Como o projeto Rails 5.2: rescue_from Exception -> Haystack.add_exception ->
# redirect para a página de erro
class ErrosRedirectController < ApplicationController
  rescue_from Exception, with: :redirecionar_erro

  def show
    raise ErroDeIntegracao, "Erro tratado com redirect (#{marca})"
  end

  private

  def redirecionar_erro(exception)
    Haystack.add_exception(exception)
    redirect_to erro_servidor_url(modo: modo, marca: marca)
  end
end
