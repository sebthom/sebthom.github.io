#!/bin/sh
set -eu

GH_TOKEN="${GH_TOKEN}" #required
CERTDB_IN_TGZ="${CERTDB_IN_TGZ:-}"
CERTDB_OUT_TGZ="${CERTDB_OUT_TGZ}" # required
CERT_FQDN="${CERT_FQDN:-sebthom.github.io}"
CERT_EMAIL="${CERT_EMAIL:-}"
CERT_USE_TEST_CA="${CERT_USE_TEST_CA:-true}"
CERT_FORCE_RENEWAL="${CERT_FORCE_RENEWAL:-false}"
CERTBOT_OPTIONS="${CERTBOT_OPTIONS:-}"

# install required software
(set -x; apk add curl git)

# https://github.community/t/github-actions-bot-email-address/17204
git config --global user.name "github-actions[bot]"
git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"
git config --global --add safe.directory $PWD
git config --global url."https://$GH_TOKEN:x-oauth-basic@github.com/".insteadOf "https://github.com/"

commit_before_challenge_update=$(git rev-parse HEAD)

if [ -n "${CERTDB_IN_TGZ:-}" ]; then
  (set -x; tar xzvf "$CERTDB_IN_TGZ" -C /)
fi

cat >/tmp/pack-certdb.sh <<EOL
#!/bin/sh
set -eux
tar cvf - -C / etc/letsencrypt | gzip -9 - >$CERTDB_OUT_TGZ
EOL
chmod 755 /tmp/pack-certdb.sh

# https://eff-certbot.readthedocs.io/en/stable/using.html#pre-and-post-validation-hooks
cat >/tmp/auth-hook.sh <<EOL
#!/bin/sh
set -eu
if [ "$CERT_USE_TEST_CA" = "true" ]; then
  out_file=$PWD/letsencrypt_challenge_test
else
  out_file=$PWD/letsencrypt_challenge
fi

echo "Writing file \$out_file..."

cat >\$out_file <<EOF
---
layout: none
permalink: .well-known/acme-challenge/\$CERTBOT_TOKEN
---
\$CERTBOT_VALIDATION
EOF

git ls-files -m
git add \$out_file
git commit -m "update certbot challenge"
echo "Pushing commit to origin..."
git push origin $GITHUB_REF_NAME

echo "Waiting for publishing of HTTP Challenge https://$CERT_FQDN/.well-known/acme-challenge/\$CERTBOT_TOKEN..."
curl --retry-all-errors --retry 10 --retry-delay 10 -sSf -o /dev/null https://$CERT_FQDN/.well-known/acme-challenge/\$CERTBOT_TOKEN
echo "HTTP Challenge published successfully."
EOL
chmod 755 /tmp/auth-hook.sh

cat >/tmp/cleanup-hook.sh <<EOL
#!/bin/sh
set -eu
git reset --soft $commit_before_challenge_update
git push origin --force $GITHUB_REF_NAME
EOL
chmod 755 /tmp/cleanup-hook.sh

common_options="$CERTBOT_OPTIONS"
common_options="$common_options --agree-tos"
common_options="$common_options --no-eff-email"
common_options="$common_options --cert-name $CERT_FQDN"
common_options="$common_options --preferred-challenges http"
common_options="$common_options --manual-auth-hook /tmp/auth-hook.sh"
common_options="$common_options --manual-cleanup-hook /tmp/cleanup-hook.sh"
common_options="$common_options --deploy-hook /tmp/pack-certdb.sh"

# All issuance requests are subject to a Duplicate Certificate limit of 5 per week.
# https://letsencrypt.org/docs/duplicate-certificate-limit/
# Thus better use the test CA during development https://letsencrypt.org/docs/staging-environment/
if [ "$CERT_USE_TEST_CA" = "true" ]; then
  echo "Using Test CA..."
  echo "  --> https://letsencrypt.org/docs/staging-environment/"
  common_options="$common_options --test-cert"
else
  echo "Using Prod CA..."
fi

(set -x; certbot certificates)

# https://eff-certbot.readthedocs.io/en/stable/using.html#certbot-command-line-options
if [ -e /etc/letsencrypt/live/$CERT_FQDN/cert.pem ]; then
  [ "$CERT_FORCE_RENEWAL" = "true" ] \
    && option_force_renewal="--force-renewal" \
    || option_force_renewal=""
  (set -x; certbot renew $common_options $option_force_renewal --no-random-sleep-on-renew)
else
  [ -z "$CERT_EMAIL" ] \
    && option_email="--register-unsafely-without-email" \
    || option_email="--email $CERT_EMAIL"
  (set -x; certbot certonly $common_options $option_email --manual --domains $CERT_FQDN)
fi
