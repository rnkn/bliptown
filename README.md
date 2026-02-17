# Bliptown

## Features

- **User Registration**: Secure user registration with email verification and 2FA setup
- **Email Verification**: 24-hour expiring verification tokens
- **Payment Integration**: Stripe payment integration for 12-month subscriptions
- **Multi-user Platform**: Support for custom domains per user
- **File Management**: Upload, organize, and manage files
- **Analytics**: Track visitor statistics with GeoIP
- **Version Control**: Snapshot system for content versioning
- **2FA Support**: TOTP-based two-factor authentication

For details on user registration, see [REGISTRATION.md](REGISTRATION.md).

## Installation

Install required packages:

```shell-session
# pkg_add sqlite3 libffi md4c libqrencode png git sqlports libmaxminddb \
	curl jq monit
```

Build and install [Carton](https://metacpan.org/pod/Carton):

```shell-session
$ portgen cpan Carton
```

Install Bliptown app:

```shell-session
$ git clone /home/rnkn/git/bliptown.git
$ cd bliptown
$ carton install
$ cd etc
# cp hourly.local daily.local weekly.local \
	httpd.conf pf.conf relayd.conf monitrc motd /etc
# install -m 755 -o root -g bin etc/rc.d/bliptown_helper /etc/rc.d/
# install -m 755 -o root -g bin etc/rc.d/bliptown /etc/rc.d/
# cat <<EOF >> /etc/login.conf
bliptown:\
	:setenv=\
BLIPTOWN_SECRET=XXXXXX,\
BLIPTOWN_HEALTH_FILE=/tmp/bliptown.health,\
BLIPTOWN_HELPER_HEALTH_FILE=/tmp/bliptown_helper.health,\
BLIPTOWN_HELPER_SOCKET=/var/run/bliptown_helper.sock,\
BLIPTOWN_DOMAIN=blip.town,\
BLIPTOWN_USER_HOME=/home/bliptown/users,\
BLIPTOWN_DB=/var/db/bliptown/users.db,\
BLIPTOWN_LOG_HOME=/var/log/bliptown,\
BLIPTOWN_GEOIP_DB=/var/db/GeoIP/geolite2-country-current.mmdb,\
BLIPTOWN_MD4C_LIB=/usr/local/lib/libmd4c-html.so.0.0,\
BLIPTOWN_MD4C_HTML_LIB=/usr/local/lib/libmd4c-html.so.0.0,\
BLIPTOWN_SMTP_ADDR=smtp.example.com,\
BLIPTOWN_SMTP_PORT=587,\
BLIPTOWN_SMTP_LOGIN=username,\
BLIPTOWN_SMTP_PASS=password,\
BLIPTOWN_STRIPE_URL=https://buy.stripe.com/YOUR_PAYMENT_LINK,\

bliptown_helper:\
	:setenv=\
BLIPTOWN_HELPER_HEALTH_FILE=/tmp/bliptown_helper.health,\
BLIPTOWN_HELPER_SOCKET=/var/run/bliptown_helper.sock,\
BLIPTOWN_HELPER_PREFORK=4,\
BLIPTOWN_DOMAIN=blip.town,\
BLIPTOWN_GID=XXXX,\
BLIPTOWN_USER_HOME=/home/bliptown/users,\
BLIPTOWN_KEYPAIR_FILE=/etc/relayd-keypairs.conf,\
BLIPTOWN_ACME_FILE=/etc/acme-domains.conf:

EOF
# sh /etc/weekly.local
# rcctl enable httpd relayd bliptown_helper bliptown monit
# rcctl start httpd relayd bliptown_helper bliptown monit
```

Install optional packages:

```shell-session
# pkg_add mosh rlwrap emacs vim nano sfeed
```

## User Registration

New users can register at `/join` with username, email, and password. The registration flow includes:

1. Email verification with 24-hour expiring tokens
2. Automatic TOTP secret generation for 2FA
3. Redirect to Stripe payment page for 12-month subscription

For complete documentation, see:
- [REGISTRATION.md](REGISTRATION.md) - Usage guide and API documentation
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) - Deployment guide
- [SECURITY_REVIEW.md](SECURITY_REVIEW.md) - Security analysis

### Required Environment Variables

For email verification (optional in development):
```bash
BLIPTOWN_SMTP_ADDR=smtp.example.com
BLIPTOWN_SMTP_PORT=587
BLIPTOWN_SMTP_LOGIN=username
BLIPTOWN_SMTP_PASS=password
```

For Stripe integration:
```bash
BLIPTOWN_STRIPE_URL=https://buy.stripe.com/YOUR_PAYMENT_LINK
```

### Testing

Run registration tests:
```shell-session
$ carton exec -- perl t/registration.t
```
