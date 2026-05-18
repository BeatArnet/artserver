FROM php:8.3-apache

ARG APP_UID=33
ARG APP_GID=33

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libcurl4-openssl-dev \
        libonig-dev; \
    docker-php-ext-install -j"$(nproc)" curl mbstring; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    current_gid="$(getent group www-data | cut -d: -f3)"; \
    if [ "$current_gid" != "${APP_GID}" ]; then groupmod -o -g "${APP_GID}" www-data; fi; \
    current_uid="$(id -u www-data)"; \
    if [ "$current_uid" != "${APP_UID}" ]; then usermod -o -u "${APP_UID}" -g "${APP_GID}" www-data; fi; \
    a2enmod headers rewrite remoteip; \
    sed -ri 's!/var/www/html!/app!g' /etc/apache2/sites-available/000-default.conf; \
    sed -ri 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf; \
    sed -ri 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-available/000-default.conf

COPY apache-menueplan.conf /etc/apache2/conf-available/menueplan.conf
COPY php-menueplan.ini /usr/local/etc/php/conf.d/menueplan.ini

RUN a2enconf menueplan

WORKDIR /app

HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=30s \
    CMD php -r "exit(@file_get_contents('http://127.0.0.1:8080/api.php?type=status') === false ? 1 : 0);"
