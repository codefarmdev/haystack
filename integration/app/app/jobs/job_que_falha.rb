# Job (adapter :async) que sempre falha: o Haystack deve capturar o erro
class JobQueFalha < ActiveJob::Base
  class Falha < StandardError
  end

  def perform(marca)
    raise Falha, "Falha no job de integração (#{marca})"
  end
end
