# Como o projeto Rails 6.1: rescue_from Exception -> Haystack.add_exception ->
# render da página de erro com status 500
class ErrosRenderController < ApplicationController
  rescue_from Exception, with: :renderizar_erro

  def show
    raise ErroDeIntegracao, "Erro tratado com render (#{marca})"
  end

  private

  def renderizar_erro(exception)
    Haystack.add_exception(exception)
    render 'paginas/erro', status: 500
  end
end
