#!/bin/sh

api_baseurl="${API_BASEURL:-https://api.porkbun.com/api/json/v3}"
keys_file="${PORKBUN_KEYS:-/etc/ssl/private/porkbun-keys.json}"

if [ $# -ne 5 ]; then
	echo "Usage: $(basename "$0") method type ident token auth" 1>&2
	exit 85
fi

method=$1
type=$2
ident=$3
auth=$5

case $ident in
	(\*.*) ident=${ident#\*.} ;;
esac

record=_acme-challenge
zone=$ident

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

find_zone() {
	while true; do
		res=$(call_api "dns/retrieve/$zone" .)
		status=$(echo "$res" | jq -r .status)

		if [ "$status" = SUCCESS ]; then
			return 0
		fi

		case $zone in
			(*.*.*)
				record=$record.${zone%%.*}
				zone=${zone#*.}
				;;
			(*)
				return 1
				;;
		esac
	done
}

find_zone || {
	echo "No zone found for $ident ($status)" 1>&2
	exit 1
}

case "$method" in
	(begin)
		res=$(call_api "dns/create/$zone" --arg content "$auth" --arg name "$record" '. + { name: $name, type: "TXT", content: $content }')
		status=$(echo "$res" | jq -r .status)

		if [ ! "$status" = "SUCCESS" ]; then
			echo "$res" | jq
			exit 1
		fi

		count=0
		while sleep 5; do
			check_record && exit 0
			[ $count -le 12 ] || exit 1
			count=$((count + 1))
		done
		;;

	(done|failed)
		res=$(call_api "dns/deleteByNameType/$zone/TXT/$record")

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
