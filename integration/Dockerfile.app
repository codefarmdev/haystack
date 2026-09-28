# App Rails de integração. A imagem só leva o código do app; as gems são
# instaladas na subida (bin/iniciar) num volume nomeado por entrada da matriz,
# porque as gems do Haystack vêm do repositório montado em /haystack.
ARG RUBY_VERSION=3.2
FROM ruby:${RUBY_VERSION}

# O repositório montado pertence a outro usuário: sem isso o `git ls-files`
# dos gemspecs falha
RUN git config --global --add safe.directory '*'

ENV RAILS_ENV=production \
    RACK_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    LANG=C.UTF-8

WORKDIR /app
COPY app/ /app/
RUN chmod +x /app/bin/iniciar

EXPOSE 3000
CMD ["/app/bin/iniciar"]
