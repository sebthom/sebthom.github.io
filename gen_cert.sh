#!/bin/sh
set -eu

CERT_ARCHIVE_IN="${CERT_ARCHIVE_IN:-/workdir/certdb.tar.gz}"
CERT_ARCHIVE_OUT="${CERT_ARCHIVE_OUT:-$CERT_ARCHIVE_IN}"
CERT_FQDN="${CERT_FQDN:-sebthom.github.io}"
CERT_EMAIL="${CERT_EMAIL:-}"
CERT_USE_TEST_CA="${CERT_USE_TEST_CA:-true}"
CERT_FORCE_RENEWAL="${CERT_FORCE_RENEWAL:-false}"
CERTBOT_OPTIONS="${CERTBOT_OPTIONS:-}"

if [ -e "$CERT_ARCHIVE_IN" ]; then
  (set -x; tar xzvf "$CERT_ARCHIVE_IN" -C /)
fi

echo "#!/bin/sh" >/tmp/pack_certdb.sh
echo "set -eux" >>/tmp/pack_certdb.sh
echo "tar cvf - -C / etc/letsencrypt | gzip -9 - >$CERT_ARCHIVE_OUT" >>/tmp/pack_certdb.sh
echo "base64 -w 0 $CERT_ARCHIVE_OUT >$CERT_ARCHIVE_OUT.base64"       >>/tmp/pack_certdb.sh
chmod 755 /tmp/pack_certdb.sh

common_options="$CERTBOT_OPTIONS"
common_options="$common_options --agree-tos"
common_options="$common_options --no-eff-email"
common_options="$common_options --cert-name $CERT_FQDN"
common_options="$common_options --preferred-challenges http"
common_options="$common_options --deploy-hook /tmp/pack_certdb.sh"

# All issuance requests are subject to a Duplicate Certificate limit of 5 per week.
# https://letsencrypt.org/docs/duplicate-certificate-limit/
# Thus better use the test CA during development https://letsencrypt.org/docs/staging-environment/
if [ "$CERT_USE_TEST_CA" = "true" ]; then
  echo "Using Test CA..."
  echo "  --> https://letsencrypt.org/docs/staging-environment/"
  common_options="$common_options --test-cert"
fi

(set -x; certbot certificates)

# https://eff-certbot.readthedocs.io/en/stable/using.html#certbot-command-line-options
if [ -e /etc/letsencrypt/live/$CERT_FQDN/cert.pem ]; then
  [ "$CERT_FORCE_RENEWAL" = "true" ] \
    && option_force_renewal="--force-renewal" \
    || option_force_renewal=""
  (set -x; certbot renew $common_options $option_force_renewal --no-random-sleep-on-renew --manual-auth-hook false)
else
  [ -z "$CERT_EMAIL" ] \
    && option_email="--register-unsafely-without-email" \
    || option_email="--email $CERT_EMAIL"
  (set -x; certbot certonly $common_options $option_email --manual --domains $CERT_FQDN)
fi
