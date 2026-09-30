#!/bin/sh

api_baseurl="${API_BASEURL:-https://api.porkbun.com/api/json/v3}"
keys_file="${PORKBUN_KEYS:-/etc/ssl/private/porkbun-keys.json}"

if [ $# -ne 5 ]
then
	echo "Usage: $(basename "$0") method type ident token auth" 1>&2
	exit 85
fi

method=$1
type=$2
ident=$3
auth=$5

[ "$type" = "dns-01" ] || exit 1

call_api() {
	endpoint=$1
	shift
	jq "$@" < "$keys_file" |
		curl -sS -X POST -H 'Content-Type: application/json' -d @- -m 30 "$api_baseurl/$endpoint"
}

check_record() {
	dig +short TXT "_acme-challenge.$ident" | grep -q "$auth"
}

case "$method" in
	(begin)
		res=$(call_api "dns/create/$ident" --arg content "$auth" '. + { name: "_acme-challenge", type: "TXT", content: $content }')

		status=$(echo "$res" | jq -r .status)
		if [ ! "$status" = "SUCCESS" ]
		then
			echo "$res" | jq
			exit 1
		fi

		count=0
		while sleep 5
		do
			check_record && exit 0
			[ $count -le 12 ] || exit 1
			count=$((count + 1))
		done
		;;

	(done|failed)
		res=$(call_api "dns/deleteByNameType/$ident/TXT/_acme-challenge")

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
