# Dev container image. Extends the same base as php-fpm but configured
# as a development shell, not a server. Does not run php-fpm.
FROM ghcr.io/vanilla/php:8.3

ARG WWWGROUP=1000
ARG WWWUSER=1000
# GID of the docker group on the host. Defaults to 999 (Ubuntu / WSL2 default).
# Override with DOCKER_GID=$(getent group docker | cut -d: -f3) in your environment.
ARG DOCKER_GID=999

RUN groupmod -o -g $WWWGROUP www-data \
    && usermod -o -u $WWWUSER -g $WWWGROUP -s /bin/bash www-data \
    # Create a docker group matching the host GID so www-data can use the
    # mounted Docker socket without sudo.
    && groupadd -f -g $DOCKER_GID docker \
    && usermod -aG docker www-data

RUN rm -f /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        sudo \
        vim \
        less \
        jq \
        ca-certificates \
        docker.io \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN echo "www-data ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/www-data \
    && chmod 0440 /etc/sudoers.d/www-data \
    && mkdir -p /var/www \
    && chown www-data:www-data /var/www

COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

ENV SHELL=/bin/bash

# Create the workspace tree as root and hand it to www-data before the USER
# switch. WORKDIR alone creates the path as root, which causes Docker to
# initialise named volumes (node_modules, .yarn/berry) with root ownership,
# leading to EACCES errors at runtime.
RUN mkdir -p \
        /srv/vanilla-repositories/vanilla/node_modules \
        /srv/vanilla-repositories/vanilla/.yarn/berry \
    && chown -R www-data:www-data /srv/vanilla-repositories

WORKDIR /srv/vanilla-repositories/vanilla

USER www-data
