# syntax=docker/dockerfile:1

# Verify this tag matches the PHP version required by pimcore/demo's composer.json
# before the first production build.
ARG PIMCORE_IMAGE_TAG=php8.3-supervisord-latest

FROM composer:2 AS build
WORKDIR /app
# Pins to whatever pimcore/demo's latest tagged release resolves to at build time.
# Once the project is stable, replace this with a committed composer.json/composer.lock
# for reproducible builds instead of always pulling latest.
RUN composer create-project --no-scripts --no-dev --prefer-dist --no-interaction pimcore/demo .
RUN composer dump-autoload --optimize --no-dev --classmap-authoritative

FROM pimcore/pimcore:${PIMCORE_IMAGE_TAG}
WORKDIR /var/www/html

COPY --from=build --chown=www-data:www-data /app /var/www/html
COPY --chmod=755 docker/docker-entrypoint.sh /usr/local/bin/pimcore-docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/pimcore-docker-entrypoint.sh"]
