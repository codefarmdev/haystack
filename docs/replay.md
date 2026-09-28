# Replay

O replay é a gravação do que o usuário viu e fez na página (DOM, cliques,
digitação, rolagem, rede e console), reproduzida no Farmer como um vídeo. Não
é um vídeo de verdade: o SDK grava as mudanças do DOM (via
[rrweb](https://github.com/rrweb-io/rrweb)) e o player as reconstrói.

## Como funciona

```
                buffer em memória (últimos 60–120 s)
página ──▶ SDK ─────────────────────────────────────┐
                                                    │ erro de JS, ou resposta com
                                                    │ header X-Haystack-Event-Id
                                                    ▼
                            envia o buffer ao Farmer e continua gravando
                            por replay_after_error_seconds (30 s)
                                                    │
                                                    ▼
                            encerra o replay e começa um buffer novo
```

1. O SDK grava continuamente num **buffer** no navegador e não envia nada.
2. Quando acontece um **erro**, o buffer vai para o Farmer, ligado ao erro
   (`error_ids`), e a gravação continua por mais 30 s.
3. Depois disso o replay termina e um buffer novo começa, pronto para o
   próximo erro.

No Farmer, a agulha mostra o replay na aba *Replay*, e **Haystack > Replays**
lista todos.

### Quanto tempo antes do erro

Entre 60 e 120 s. O SDK original do Sentry apagava o buffer a cada minuto e o
replay trazia de 0 a 60 s. O bundle do Haystack foi alterado para descartar só
o trecho anterior ao penúltimo "checkout" (ver
[desenvolvimento.md](desenvolvimento.md#o-bundle-do-sdk-do-navegador)).

Limite do SDK: se o buffer passa de **20 MB**, ele é descartado e a gravação
recomeça no próximo checkout. Isso acontece em páginas com muitíssimas mudanças
no DOM (ex.: a própria tela de replay do Farmer, gráficos animados). Marque
essas áreas com `data-haystack-block` (ver [Privacidade](#privacidade-e-o-que-não-gravar)).

## Erros de JS

Funcionam em qualquer app com o SDK (asset pipeline). O replay mostra a página
atual desde que ela carregou; em apps com Turbolinks, também as páginas
anteriores da mesma aba.

## Erros de backend

O servidor avisa o navegador pelo header `X-Haystack-Event-Id`, e o SDK envia o
replay. Isso só funciona quando o navegador continua na mesma página para ler
esse header, ou seja, quando a navegação é feita por **XHR/fetch**:

| Situação | Replay do erro de backend |
|---|---|
| Turbolinks/Turbo, erro renderizado (`render ..., status: 500`) | sim |
| Chamada AJAX/fetch que falha | sim |
| Formulário ou link comum (página inteira recarrega) | não |
| Turbolinks com `redirect_to` para a página de erro | não (o XHR segue o redirect e o header se perde) |
| Layout de erro com assets rastreados diferentes do normal | não (o Turbolinks recarrega a página inteira) |

Numa navegação comum, o navegador descarta a página, e o buffer com ela, antes
de a resposta com erro chegar. O **erro** chega ao Farmer normalmente em todos
os casos; só o replay fica faltando.

O header é colocado para erros não tratados e para qualquer
`Haystack.capture_exception` / `Haystack.add_exception` feito durante a
requisição (inclusive em `rescue_from`).

Para um app com Turbolinks ter replay dos erros de backend:

```erb
<%# layouts/application.html.erb e layouts/error.html.erb: os mesmos assets rastreados %>
<%= stylesheet_link_tag 'application', media: 'all', 'data-turbolinks-track': 'reload' %>
<%= javascript_include_tag 'application', 'data-turbolinks-track': 'reload' %>
```

```ruby
def render_error(exception)
  Haystack.capture_exception(exception)
  render 'home/error', layout: 'error', status: 500   # render, não redirect
end
```

## Modos (no cadastro do projeto no Farmer)

| Modo | O que é gravado |
|---|---|
| Desligado | nada; o Farmer descarta qualquer replay recebido |
| Só com erro (padrão) | só os replays de erro |
| Com erro e % das sessões | também uma fração das sessões inteiras, com ou sem erro |

Hoje o modo é aplicado **no Farmer** (ele descarta o que não quer). O SDK dos
outros apps continua gravando o buffer conforme o `config.js` deles. O próprio
Farmer lê o modo do banco para decidir o que o navegador grava.

## Privacidade e o que não gravar

O replay grava a tela como ela é: textos e links, **inclusive parâmetros de
URL** que aparecem na página (ex.: um link `?token=...`). O que é digitado em
campos de formulário aparece como `***` (padrão do SDK); os textos da página
não, a menos que `config.js.mask_all_text = true`.

| Atributo/classe no HTML | Efeito |
|---|---|
| `data-haystack-block` ou `class="haystack-block"` | o elemento vira um retângulo vazio no replay (nada dentro é gravado) |
| `data-haystack-mask` ou `class="haystack-mask"` | textos trocados por `*` |
| `data-haystack-ignore` ou `class="haystack-ignore"` | não grava o que é digitado no campo |

Use `data-haystack-block` em dados sensíveis (cartão, documentos) e em áreas que
mudam o tempo todo (players, gráficos em tempo real), para não estourar o
buffer.



## Cliques mortos e repetidos

O Farmer marca no replay:

- **clique morto:** um clique em link/botão que não mudou nada na página em 7 s;
- **clique repetido (rage click):** um clique morto com 5 ou mais cliques seguidos.

## Onde está cada parte

| Parte | Arquivo |
|---|---|
| Injeção do SDK, header, fim da gravação após o erro | `haystack-rails/lib/haystack/rails/middleware/injector.rb` |
| SDK do navegador (com os patches do Haystack) | `haystack-rails/app/assets/javascripts/haystack/bundle.tracing.replay.min.js` |
| Marcação da requisição com o erro | `Haystack.capture_exception` em `haystack/lib/haystack.rb` |
| Recebimento e armazenamento | Farmer: `HaystackV2::PayloadProcessorService`, `ReplayRecording`, `ReplaySegment` |
