# Bliptown

## Installation

Install required packages:

```shell-session
# pkg_add sqlite3 libffi md4c libqrencode png git sqlports curl jq monit
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
BLIPTOWN_GEOIP_DB=/usr/local/share/bliptown/geolite2-country-current.mmdb,\
BLIPTOWN_MD4C_LIB=/usr/local/lib/libmd4c-html.so.0.0,\
BLIPTOWN_MD4C_HTML_LIB=/usr/local/lib/libmd4c-html.so.0.0,\

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
# rcctl enable httpd relayd bliptown_helper bliptown monit
# rcctl start httpd relayd bliptown_helper bliptown monit
```

Install optional packages:

```shell-session
# pkg_add mosh goaccess emacs vim nano sfeed
```
