#!/bin/sh
set -e

# Idempotent first-boot installer for the Pimcore skeleton package.
# Marker file lives on the persisted /var/www/html/var volume, so it survives
# redeploys but not a volume wipe (which is the intended "reinstall" trigger).
MARKER=/var/www/html/var/.pimcore-installed

wait_for_mysql() {
  echo "Waiting for MySQL at ${MYSQL_HOST:-mariadb}:${MYSQL_PORT:-3306}..."
  until php -r "new PDO('mysql:host=${MYSQL_HOST:-mariadb};port=${MYSQL_PORT:-3306}', '${MYSQL_USER}', '${MYSQL_PASSWORD}');" 2>/dev/null; do
    sleep 2
  done
}

if [ ! -f "$MARKER" ]; then
  wait_for_mysql

  echo "Running first-time Pimcore installation..."
  # SkeletonProfile reads DB connection from DATABASE_URL and admin credentials from
  # PIMCORE_ADMIN_USER/PIMCORE_ADMIN_PASSWORD, all set as container env vars already.
  vendor/bin/pimcore-install --install-profile='App\Installer\SkeletonProfile' --no-interaction

  php bin/console cache:clear --no-interaction

  touch "$MARKER"
  echo "Pimcore installation complete."
else
  echo "Pimcore already installed, skipping installer."
fi

# Hand off to the base image's own entrypoint/supervisor (starts php-fpm, cron, etc.).
# Verify this matches the actual entrypoint of pimcore/pimcore:${PIMCORE_IMAGE_TAG}
# before relying on this in production.
exec docker-php-entrypoint "$@"
