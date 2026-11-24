# syntax=docker/dockerfile:1
#
# Mautic 7.2.2 for Railway: web (Apache), the cron jobs and the messenger
# workers in one container, because they share config/local.php, uploaded
# media and import files, and a Railway volume belongs to one service.
#
# Base: the official image mautic/mautic:7.2.2-apache pinned by digest
# (build of 2026-11-19). To upgrade, change the tag and digest together
# (Docker Hub, mautic/mautic) and redeploy; migrations run at start.
FROM mautic/mautic:7.2.2-apache@sha256:cb5a72a63c855917c2c6eca65cd368b02d8d491bc135d3834e85ba5d575d789c

# HTTP API mail transports (Railway allows outbound SMTP only on Pro):
# Amazon SES, SendGrid, Postmark, Mailgun and Brevo via Symfony Mailer DSNs.
RUN cd /var/www/html \
 && COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_PROCESS_TIMEOUT=1200 composer require --no-interaction --no-scripts --update-no-dev \
      symfony/amazon-mailer:~7.4.0 symfony/sendgrid-mailer:~7.4.0 symfony/postmark-mailer:~7.4.0 \
      symfony/mailgun-mailer:~7.4.0 symfony/brevo-mailer:~7.4.0 \
 && rm -rf var/cache/* /root/.composer/cache \
 && chown -R www-data:www-data /var/www/html/vendor /var/www/html/var /var/www/html/composer.json /var/www/html/composer.lock

# Everything that must persist lives on one volume at /data. Keep the image's
# defaults as seeds; railway-start.sh links the app folders to the volume at
# runtime (the base image declares them as VOLUMEs, so they are not changed
# at build time).
RUN mkdir -p /opt/railway-seed \
 && cp -a /var/www/html/config /opt/railway-seed/config \
 && cp -a /var/www/html/docroot/media/images /opt/railway-seed/images \
 && cp -a /var/www/html/docroot/media/files /opt/railway-seed/files

COPY --chmod=0755 railway-start.sh mautic-scheduler.sh /railway/
COPY --chmod=0644 mautic-admin.php railway-healthz.php /railway/
COPY --chmod=0644 railway-healthz.conf /etc/apache2/conf-available/railway-healthz.conf
RUN a2enconf railway-healthz >/dev/null

ENV PORT=80
EXPOSE 80
ENTRYPOINT ["/railway/railway-start.sh"]
