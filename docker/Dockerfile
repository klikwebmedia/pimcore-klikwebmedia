# syntax=docker/dockerfile:1

# pimcore/skeleton's composer.json constrains PHP, so the build stage must use the same
# PHP version as the runtime image (composer's own PHP interpreter is what gets checked
# against platform requirements, not the target runtime).
ARG PIMCORE_IMAGE_TAG=php8.5-supervisord-latest

FROM pimcore/pimcore:${PIMCORE_IMAGE_TAG} AS build
WORKDIR /app
# Pins to whatever pimcore/skeleton's latest tagged release resolves to at build time.
# Once the project is stable, replace this with a committed composer.json/composer.lock
# for reproducible builds instead of always pulling latest.
RUN composer create-project --no-scripts --no-dev --prefer-dist --no-interaction pimcore/skeleton .
RUN composer dump-autoload --optimize --no-dev --classmap-authoritative

FROM pimcore/pimcore:${PIMCORE_IMAGE_TAG}
WORKDIR /var/www/html

COPY --from=build --chown=www-data:www-data /app /var/www/html
COPY --chmod=755 docker/docker-entrypoint.sh /usr/local/bin/pimcore-docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/pimcore-docker-entrypoint.sh"]
# The supervisord-flavor base image's own CMD (which we override with our ENTRYPOINT above)
# is ["/usr/bin/supervisord"] — restate it so it's passed through as "$@" and actually starts
# php-fpm/cron/workers after our install logic runs, instead of exiting immediately.
CMD ["/usr/bin/supervisord"]
