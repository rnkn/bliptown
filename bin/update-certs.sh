#!/bin/sh

production=false
staging=false

[ $(hostname) = avalon.blip.town ] && production=true
[ $(hostname) = epoch.staging-blip.town ] && staging=true

if $production; then
	expected_A_record=46.225.163.173
	expected_AAAA_record=2a01:4f8:1c19:6498::1
elif $staging; then
	expected_A_record=77.42.77.0
	expected_AAAA_record=2a01:4f9:c013:4744::1
fi

renew_cert() {
	domain=$1
	wildcard=${2:-false}
	issue=false
	test -n "$domain" || return 1

	if $wildcard; then
		hook=/usr/local/www/bliptown/bin/nsupdate.sh
		set -- "$domain" "*.$domain"
	else
		export UACME_CHALLENGE_PATH=/var/www/challenge
		hook=/usr/pkg/libexec/uacme/uacme.sh
		set -- "$domain"
	fi

	if [ -d "/etc/ssl/private/${domain}" ]; then
		/usr/pkg/bin/uacme -c /etc/ssl -iod 30 check "$domain"
		case $? in
			(0)		issue=true ;;
			(2)		echo "Check certificate failed: $domain"; return 1 ;;
		esac
	else
		issue=true
	fi

	if $issue; then
		ok=true

		$ok && dig "$domain" A +short | grep -qx "$expected_A_record" || ok=false
		$ok && dig "$domain" AAAA +short | grep -qx "$expected_AAAA_record" || ok=false
		$ok || { echo "DNS records don't match: $domain" >&2; return 1; }

		/usr/pkg/bin/uacme -c /etc/ssl -iod 30 -h "$hook" issue "$@"

		case $? in
			(0)		echo "Issued new certificate: $domain" ;;
			(2)		echo "Issue certificate failed: $domain" >&2; return 1 ;;
		esac

		chown -R :nginx "/etc/ssl/private/${domain}"
		chmod -R g+r "/etc/ssl/private/${domain}"
		chmod g+x "/etc/ssl/private/${domain}"
	fi
}

if $production; then
	renew_cert blip.town true

	for link in /home/bliptown/domains/*; do
		domain=$(basename "$link")
		renew_cert "$domain" false
	done

elif $staging; then
	renew_cert staging-blip.town true
fi
