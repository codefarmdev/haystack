# Suíte de integração do Haystack 1.0

Testes de ponta a ponta das gems `haystack` e `haystack-rails` num app Rails de
verdade (modo production, assets precompilados, puma), com um Chrome de verdade
e um Farmer falso que recebe e decodifica tudo o que o SDK envia. Roda numa
matriz de versões de Ruby e Rails, a mesma dos projetos que usam o Haystack.

## O que é testado

| Grupo | Cenário |
|---|---|
| A. boot e assets | o HTML traz `<script src="/assets/haystack/bundle.tracing.replay.min-<digest>.js">` e o script de init antes do `</head>`; o bundle é servido com 200; JSON não recebe script |
| B. erro não tratado | evento `ruby` com tipo/mensagem, stacktrace com o arquivo do app, `request.url`, `transaction`; header `X-Haystack-Event-Id` igual ao `event_id`; página 500 estática recebe o SDK; endpoint JSON |
| C. erro tratado (`rescue_from` + `Haystack.add_exception`) | com `render` (como o projeto Rails 6.1): evento + header na resposta 500; com `redirect_to` (como o projeto Rails 5.2): evento + header no 302 |
| D. filtro de parâmetros | `password`/`cartao` viram `[FILTERED]` e não aparecem em nenhum envelope (busca no JSON inteiro recebido), via query string, POST e no navegador (replay mascara inputs) |
| E. usuário | com o cookie `usuario`, o evento traz id/email/username e o script injetado chama `setUser`; sem cookie não herda usuário de outra requisição |
| F. transações | `Controller#action` com spans (`view.process_action.action_controller`, `template.render*`) e os extras do fork (`params`, `session_data`, `client_ip`, `memory_usage`, `view_runtime`); `/saude` sem transação (`traces_sampler`); `ErroIgnorado` (excluded_exceptions) sem evento nem header; erro em ActiveJob vira evento |
| G. navegador | pageload vira transação `javascript`; erro de JS vira evento + `replay_event` (`replay_type: buffer`, `error_ids` com o evento) + gravação com full snapshot; o replay para depois de `replay_after_error_seconds`, nenhum replay é enviado sem erro, e um erro novo abre outro `replay_id`; usuário no evento JS |
| H. erro do backend numa navegação | Turbolinks: visita XHR que cai no erro tratado com render → replay com `error_ids` contendo o evento ruby e com o que aconteceu **antes** (digitação, página inicial e página 2); clássico: replay da página de erro |
| I. limitação conhecida | erro tratado com **redirect**: o evento chega, mas nenhum replay contém o id dele (em `/classico` e `/turbo`) |
| J. cliques mortos | 6 cliques no "botão morto" geram `ui.slowClickDetected` com `clickCount >= 3` (rage click) dentro do replay |

Cada cenário roda em `/turbo/...` (layout com Turbolinks, navegação por XHR) e
em `/classico/...` (layout sem Turbolinks, página inteira) quando faz sentido.

## Arquitetura

```
           rede docker "haystack-integracao-<entrada>" (nenhuma porta publicada no host)

  ┌──────────────┐  HTTP direto   ┌──────────────────────────┐  envelopes (gem Ruby)
  │ tester       │ ─────────────▶ │ aplicacao:3000           │ ───────────────────┐
  │ ruby 3.2     │                │ Rails 5.2/6.1/7.x, puma  │                    │
  │ rspec        │  WebDriver     │ RAILS_ENV=production     │                    ▼
  │ selenium     │ ──────┐        │ /haystack (repo, ro)     │        ┌─────────────────────┐
  │              │       │        └──────────────────────────┘        │ receiver:9292       │
  │              │       ▼                   ▲ páginas + bundle JS    │ Farmer falso        │
  │              │  ┌──────────────┐         │                        │ POST .../envelope   │
  │              │  │ chrome:4444  │ ────────┘                        │ GET/DELETE          │
  │              │  │ chromium     │ ────────────────────────────────▶│   /_recebidos       │
  │              │  └──────────────┘   envelopes (SDK do navegador)   └─────────────────────┘
  │              │ ───────────────────── GET /_recebidos, DELETE ───────────────▲
  └──────────────┘
```

- `receiver/receiver.rb`: Farmer falso (WEBrick). `GET /_recebidos` devolve os
  envelopes decodificados (inclusive `replay_recording` → `{"meta":{"segment_id"},"events":[rrweb]}`),
  `DELETE /_recebidos` limpa, `GET /_saude`. Com `DUMP_DIR`, grava o corpo cru
  de cada envelope (já descomprimido) em arquivos.
- `app/`: app Rails mínimo que funciona em 5.2, 6.1 e 7.x. `RAILS_VERSION`
  escolhe a versão no `Gemfile`; as gems do Haystack vêm de `/haystack` (este
  repositório montado somente leitura). Na subida (`app/bin/iniciar`) instala
  as gems (cache num volume por entrada), precompila os assets e sobe o puma.
- `spec/`: suíte RSpec rodada no container tester. Helpers em `spec/support/`
  (`receptor.rb`: cliente do receptor e esperas com polling; `http.rb`;
  `navegador.rb`: Selenium).
- O navegador acessa o app como `http://aplicacao:3000` (e não `app`: o TLD
  `.app` está na lista de HSTS preload e o Chrome força https) e envia para
  `http://receiver:9292`, o mesmo endereço que a gem usa.

## Como rodar

Pré-requisitos: Docker (no macOS, colima: `colima start --cpu 4 --memory 6`).
O repositório precisa estar sob o diretório home (o colima só monta caminhos de
`/Users/<você>`). Não precisa do `docker compose`.

```bash
integration/bin/rodar                 # matriz padrão: 2.6.4|5.2.8.1, 3.0|6.1.7.10, 3.2|6.1.7.10
integration/bin/rodar --so 2.6        # só as entradas cujo Ruby começa com 2.6
integration/bin/rodar --com-rails7    # inclui 3.3|7.2
integration/bin/rodar --so 3.2 --manter            # deixa os containers de pé para depurar
integration/bin/rodar --so 3.2 --exemplo "Turbolinks"   # filtra exemplos (rspec -e)
integration/bin/rodar --so 3.2 --rspec "spec/backend_spec.rb"
integration/bin/rodar --fixtures /caminho/fixtures  # copia os envelopes crus recebidos
```

A primeira execução de cada entrada instala as gems (no Ruby 2.6 o nokogiri é
compilado do fonte) e demora alguns minutos; depois fica no volume
`haystack-integracao-bundle-<entrada>`. Cada entrada leva ~2,5 a 5 min.

No fim sai uma tabela (também em `integration/tmp/resumo.txt`) e o código de
saída é diferente de zero se alguma entrada falhou. Por entrada, em
`integration/tmp/<entrada>/`: `junit.xml`, `rspec.txt`, `tester.log`,
`app.log`, `receiver.log`, `build.log` e `envelopes/` (corpos crus).

Com `--manter`, os containers ficam como `haystack-integracao-<entrada>-{app,receiver,chrome}`.
Para rodar a suíte de novo contra eles:

```bash
docker run --rm --network haystack-integracao-ruby3-2-rails6-1-7-10 \
  -e APP_URL=http://aplicacao:3000 -e RECEIVER_URL=http://receiver:9292 -e SELENIUM_URL=http://chrome:4444 \
  -e RAILS_VERSION_APP=6.1.7.10 -e HAYSTACK_REPLAY_AFTER_ERROR_SECONDS=7 \
  -v $PWD/integration/spec:/integration/spec:ro -v $PWD/integration/.rspec:/integration/.rspec:ro \
  haystack-integracao-tester rspec spec/navegador_spec.rb
docker exec haystack-integracao-ruby3-2-rails6-1-7-10-receiver curl -s localhost:9292/_recebidos | jq .
```

`docker-compose.yml` descreve os mesmos serviços para quem preferir o compose
(ver o cabeçalho do arquivo); o `bin/rodar` não depende dele.

## Como adicionar um cenário

1. Se precisar de uma rota nova, adicione em `app/config/routes.rb` (dentro do
   `scope ':modo'` para valer em `/turbo` e `/classico`) e o controller/view.
   Coloque `params[:marca]` na mensagem de erro para o teste achar o evento.
2. Escreva o `it` em `spec/backend_spec.rb` (só HTTP) ou `spec/navegador_spec.rb`
   (Chrome). O receptor é limpo antes de cada exemplo e cada exemplo usa um
   navegador novo. Use `nova_marca`, `http_get`, `visitar`/`clicar`/`digitar`,
   `esperar_evento_ruby(marca)`, `esperar_evento_js`, `esperar_transacao(nome)`,
   `esperar_replay_do_erro(event_id)`, `eventos_rrweb(replay_id)`,
   `breadcrumbs_do_replay(replay_id)`, `wait_for_envelope { |env| ... }`.
   Nunca use `sleep` fixo para esperar algo chegar: use as esperas com polling.
3. Bug do Haystack: deixe o teste escrito e marque `pending "BUG: ..."`
   (condicionado à versão, se for o caso). O RSpec avisa quando o bug for
   corrigido (o pending passa a falhar).

## Como adicionar uma versão de Ruby/Rails à matriz

Edite `MATRIZ_PADRAO` (ou `MATRIZ_RAILS7`) em `bin/rodar`: cada entrada é
`"<tag da imagem ruby>|<versão do Rails>"`. Versão com 3 ou 4 partes é exata
(`6.1.7.10`); com 2 partes vira `~> X.Y.0`. Ajustes de gems por versão ficam no
`app/Gemfile` (ex.: Rails 5.2 usa sprockets 3.7, puma 4.3 e nokogiri 1.13;
Rails 7 precisa de `sprockets-rails`). Imagens `ruby:2.x` compilam as gems
nativas do fonte (`BUNDLE_FORCE_RUBY_PLATFORM=true`, automático no `bin/rodar`).

## Fixtures de contrato do Farmer

O receptor grava o corpo cru de cada envelope recebido. Para regenerar as
fixtures usadas nos testes do Farmer:

```bash
integration/bin/rodar --so 3.2 --fixtures /tmp/fixtures-haystack
ls /tmp/fixtures-haystack/ruby3.2-rails6.1.7.10/   # 00001-transaction.envelope, 00002-event.envelope, 00042-replay_event+replay_recording.envelope...
```

Os arquivos já estão descomprimidos (o SDK Ruby comprime com gzip os envelopes
grandes; o receptor grava o conteúdo já descomprimido). Copie os que interessam para as fixtures do Farmer.

## Bugs e limitações conhecidos (cobertos por testes)

- **Corrigido no 1.1.0 (achados por esta suíte):**
  - no Rails < 7.1, os breadcrumbs `start_processing`/`process_action` levavam
    `data.path` com a query string sem filtro (`?password=...`); agora o
    `haystack-rails` aplica o `filter_parameters` (teste D);
  - no Rails >= 7.1 (Rack 3), a página 500 estática do Rails, com headers em
    minúsculas, ficava sem o SDK (teste B);
  - ao encerrar o replay depois do erro, um envio já agendado pelo SDK
    disparava no buffer novo e mandava um segmento 0 sem erro e sem snapshot
    (acontecia sempre com `replay_after_error_seconds = 5`). O injector agora
    cancela esse envio e grava pelo menos 6 s depois do erro, porque o SDK não
    envia replays com menos de 5 s (teste G, e H no modo clássico). Rodado
    com `HAYSTACK_REPLAY_AFTER_ERROR_SECONDS=5`, o caso mais apertado.
- **Limitação: erro tratado com redirect não entra no replay.** O header vai no
  302, que o navegador (e o XHR do Turbolinks, que segue o redirect sozinho)
  não expõe ao JS; a página de destino é outra requisição. O evento chega sem
  replay (teste I).
- **Limitação: erros de JS idênticos seguidos.** O `dedupeIntegration` do SDK
  descarta um erro igual ao anterior; o teste G usa um segundo botão com outro
  erro.
- O "clique morto" repetido gera um único `ui.slowClickDetected` com
  `clickCount` > 1 (rage click); `ui.multiClick` não aparece nesse cenário.

## Problemas comuns

- **nokogiri no Ruby 2.6**: a imagem `ruby:2.6.4` (Debian buster) tem glibc
  antiga e o nokogiri pré-compilado não carrega; o `bin/rodar` define
  `BUNDLE_FORCE_RUBY_PLATFORM=true` para Ruby 2.x (compila do fonte, alguns
  minutos na primeira vez).
- **"Failed to open TCP connection to receiver:9292 (execution expired)"** no
  `app.log`: no glibc antigo a consulta DNS A/AAAA em paralelo ao DNS do Docker
  às vezes leva 5 s, e o SDK tem `open_timeout` de 1 s. O app sobe com
  `--dns-option single-request-reopen`.
- **colima e montagens**: só caminhos sob `/Users/<você>` são montáveis
  (`/tmp`, `/private/tmp` não). O repositório tem de estar no home.
- **Chrome em arm64**: use `selenium/standalone-chromium` (multi-arch); o
  `selenium/standalone-chrome` só existe para amd64. Precisa de `--shm-size 2g`.
- **`net::ERR_SSL_PROTOCOL_ERROR` no Chrome**: o host do app não pode se chamar
  `app` (HSTS preload do TLD `.app`); use `aplicacao`.
- **App não sobe**: veja `integration/tmp/<entrada>/app.log`. Para refazer as
  gems do zero: `docker volume rm haystack-integracao-bundle-<entrada>`.
- **Containers de uma execução interrompida**: o `bin/rodar` derruba os
  containers da entrada antes de subir; para limpar à mão,
  `docker rm -f $(docker ps -aq --filter name=haystack-integracao-)`.
