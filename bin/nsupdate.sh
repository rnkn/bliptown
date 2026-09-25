#!/bin/sh

API_BASEURL="${API_BASEURL:-https://api.porkbun.com/api/json/v3}"
KEYS_FILE="${PORKBUN_KEYS:-/etc/ssl/private/porkbun-keys.json}"

if [ $# -ne 5 ]; then
	echo "Usage: $(basename "$0") method type ident token auth" 1>&2
	exit 85
fi

METHOD=$1
TYPE=$2
IDENT=$3
AUTH=$5

[ "$TYPE" = "dns-01" ] || exit 1

send_api() {
	endpoint=$1
	shift
	jq "$@" < "$KEYS_FILE" |
		curl -sS -X POST -H 'Content-Type: application/json' -d @- -m 30 "$API_BASEURL/$endpoint"
}

check_record() {
	dig +short TXT "_acme-challenge.$IDENT" | grep "$AUTH"
}

case "$METHOD" in
	(begin)
		res=$(send_api "dns/create/$IDENT" --arg content "$AUTH" '. + { name: "_acme-challenge", type: "TXT", content: $content }')

		status=$(echo "$res" | jq -r .status)
		[ "$status" = "SUCCESS" ] ||
			{ echo "DNS creation rejected ($status)" 1>&2; exit 1; }

		count=0
		while sleep 5
		do
			check_record && exit 0
			[ $count -le 12 ] || exit 1
			count=$((count + 1))
		done
		;;

	(done|failed)
		res=$(send_api "dns/deleteByNameType/$IDENT/TXT/_acme-challenge")

		status=$(echo "$res" | jq -r '.status')
		[ "$status" = "SUCCESS" ] ||
			echo "DNS cleanup failed, stale TXT may remain ($status)" 1>&2
		exit 0
		;;

	(*)
		echo "$0: invalid method" 1>&2
		exit 1
		;;
esac

