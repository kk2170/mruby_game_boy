FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  bison \
  build-essential \
  ca-certificates \
  git \
  libsdl2-dev \
  pkg-config \
  rake \
  ruby \
  xauth \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY docker/entrypoint.sh /usr/local/bin/game-boy-entrypoint
RUN chmod +x /usr/local/bin/game-boy-entrypoint

ENTRYPOINT ["/usr/local/bin/game-boy-entrypoint"]
CMD ["bash"]
