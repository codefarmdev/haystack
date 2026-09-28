class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  before_action :carregar_usuario

  layout :layout_do_modo

  helper_method :modo, :marca

  private

  # /turbo/... usa o layout com Turbolinks; /classico/... o layout sem
  def modo
    params[:modo] == 'classico' ? 'classico' : 'turbo'
  end

  def layout_do_modo
    modo
  end

  # Identificador do teste que fez a requisição; vai nas mensagens de erro para
  # os testes acharem o evento certo no receptor
  def marca
    params[:marca].presence || 'sem-marca'
  end

  # Login falso: com o cookie usuario=<id> há um @current_user (lido pelo
  # injector do SDK do navegador) e o usuário vai para o escopo do Haystack
  def carregar_usuario
    id = cookies[:usuario]
    return if id.blank?

    @current_user = Usuario.new(id.to_i, "Usuária #{id}", "usuario#{id}@exemplo.com.br")
    Haystack.set_user(id: @current_user.id, email: @current_user.email, username: @current_user.name)
  end
end
