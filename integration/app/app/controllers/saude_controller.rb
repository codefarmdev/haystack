# Health check: o traces_sampler do initializer não gera transação para ele
class SaudeController < ActionController::Base
  def show
    render plain: 'ok'
  end
end
