# syntax=docker/dockerfile:1

# pimcore/demo's composer.json constrains PHP to ~8.2/~8.3, so the build stage must use
# the same PHP version as the runtime image (composer's own PHP interpreter is what gets
# checked against platform requirements, not the target runtime, so a generic composer:2
# image running PHP 8.5 fails dependency resolution here).
ARG PIMCORE_IMAGE_TAG=php8.3-supervisord-latest

FROM pimcore/pimcore:${PIMCORE_IMAGE_TAG} AS build
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
