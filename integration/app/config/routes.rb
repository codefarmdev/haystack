Rails.application.routes.draw do
  root to: redirect('/turbo')

  get 'saude', to: 'saude#show'

  # Os mesmos cenários em dois modos: /turbo usa o layout com Turbolinks (as
  # navegações são XHR) e /classico o layout sem Turbolinks (página inteira)
  scope ':modo', constraints: { modo: /turbo|classico/ } do
    get '/', to: 'paginas#index', as: :inicio
    get 'pagina2', to: 'paginas#pagina2', as: :pagina2
    get 'formulario', to: 'paginas#formulario', as: :formulario
    post 'formulario', to: 'paginas#enviar'
    get 'erro-servidor', to: 'paginas#erro_servidor', as: :erro_servidor

    get 'erro', to: 'erros#nao_tratado', as: :erro_nao_tratado
    get 'erro-ignorado', to: 'erros#ignorado', as: :erro_ignorado
    get 'job', to: 'erros#job', as: :job_com_erro
    get 'api/ok', to: 'erros#api_ok', as: :api_ok
    get 'api/erro', to: 'erros#api_erro', as: :api_erro

    get 'erro-render', to: 'erros_render#show', as: :erro_render
    get 'erro-redirect', to: 'erros_redirect#show', as: :erro_redirect
  end
end
