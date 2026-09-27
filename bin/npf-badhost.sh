#!/bin/sh

set -eu

blacklist=/etc/blacklist.txt

lists="
https://www.binarydefense.com/banlist.txt
https://rules.emergingthreats.net/blockrules/compromised-ips.txt
https://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level2.netset
https://www.spamhaus.org/drop/drop.txt
https://www.spamhaus.org/drop/edrop.txt
https://isc.sans.edu/api/threatlist/shodan/?text
https://feodotracker.abuse.ch/downloads/ipblocklist.txt
https://sslbl.abuse.ch/blacklist/sslipblacklist.txt
"

raw=$(mktemp)
clean=$(mktemp)
trap 'rm -f $raw $clean' EXIT INT TERM

for url in $lists; do
	ftp -o - "$url" >> "$raw" 2>/dev/null ||
		echo "npf-badhost: WARNING: failed to fetch $url" >&2
done

grep -Eo '((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])(/[0-9]{1,2})?' < "$raw" |
	grep -vE '^(0\.|10\.|100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.|127\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.0\.2\.|192\.168\.|198\.1[89]\.|22[4-9]\.|2[3-5][0-9]\.)' |
	sort -u > "$clean"

install -m 644 "$clean" "$blacklist"
lines=$(wc -l < "$clean")

npfctl reload
echo "npf-badhost: $lines entries loaded into <blacklist>"
