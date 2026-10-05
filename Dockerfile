# syntax=docker/dockerfile:1
# campfire-phoenix:app — `docker build -t campfire-phoenix:app .` (native arch; arm64 on Apple Silicon).
# Runs as uid 1000 with /rails/storage/{db,files} bind-mounted, like the Rails image (bench/run).
ARG ELIXIR_IMAGE=hexpm/elixir:1.19.0-erlang-28.1-debian-bookworm-20260610-slim
ARG RUNTIME_IMAGE=debian:bookworm-20260610-slim

FROM ${ELIXIR_IMAGE} AS build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
# Source maps (and their .gz) are only for devtools: ~3 MB the image needn't carry.
RUN find priv/static \( -name '*.map' -o -name '*.map.gz' \) -delete
COPY lib lib
COPY config/runtime.exs config/
COPY rel rel
RUN mix compile --warnings-as-errors && mix release

FROM ${RUNTIME_IMAGE}
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 libssl3 libncurses6 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 1000 --user-group --home-dir /tmp --no-create-home campfire \
    && mkdir -p /rails/storage/db /rails/storage/files && chown -R 1000:1000 /rails/storage

WORKDIR /app
COPY --from=build --chown=root:root /app/_build/prod/rel/campfire ./
USER 1000:1000
ENV HOME=/tmp LANG=C.UTF-8 RELEASE_DISTRIBUTION=none RELEASE_TMP=/tmp
EXPOSE 80
CMD ["/app/bin/campfire", "start"]
