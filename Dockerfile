FROM ubuntu:xenial

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    gnupg \
    gcc \
    make \
    m4 \
    curl \
    unzip \
    libncurses-dev \
    libreadline-dev \
    libssl-dev \
    python3-pip \
    git \
    vim \
    locales \
    jq && \
  pip3 install yq && \
  locale-gen en_US.UTF-8 && \
  curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
  echo "deb http://apt.postgresql.org/pub/repos/apt xenial-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
  apt-get update && \
  apt-get install -y postgresql-9.4

# travis has some kind of 'postgresql-check-db-dir' script, but I can't
# find that in any packages, so let's fake it
RUN ln -s $(which true) /usr/local/bin/postgresql-check-db-dir

RUN useradd -d /home/builder -m builder && \
    mkdir -p /home/builder/.travis

COPY .travis.yml /home/builder/.travis.yml
COPY .travis/* /home/builder/.travis/

RUN chown -R builder /home/builder/

# convert some of .travis.yml into a script
WORKDIR /home/builder

RUN echo "#!/usr/bin/env bash" > /opt/install_deps.sh && \
    echo "set -ex" >> /opt/install_deps.sh && \
    yq -r '.env.global[]' .travis.yml | sed -e 's/^/export /' >> /opt/install_deps.sh && \
    yq -r '.before_install[]' .travis.yml >> /opt/install_deps.sh && \
    yq -r '.install[]'        .travis.yml >> /opt/install_deps.sh && \
    chmod +x /opt/install_deps.sh

RUN echo "#!/usr/bin/env bash" > /opt/entrypoint.sh && \
    echo "set -e" >> /opt/entrypoint.sh && \
    yq -r '.env.global[]' .travis.yml | sed -e 's/^/export /' >> /opt/entrypoint.sh && \
    yq -r '.before_install[]' .travis.yml | sed -e 's/$/ || true/' >> /opt/entrypoint.sh && \
    echo 'exec "$@"' >> /opt/entrypoint.sh && \
    chmod +x /opt/entrypoint.sh

USER builder
ENV HOME /home/builder
ENV TRAVIS_OS_NAME linux
ENV PATH "/usr/lib/postgresql/9.4/bin:$PATH"

ENV TRAVIS_BUILD_DIR /home/builder
ARG LUA=lua5.1
ARG LUA_32BITS=no
RUN /opt/install_deps.sh

COPY . /home/builder/pgmoon
USER root
RUN chown -R builder /home/builder/pgmoon
USER builder
WORKDIR /home/builder/pgmoon

ENTRYPOINT ["/opt/entrypoint.sh"]
CMD ["/bin/bash","-c","luarocks make && busted"]
