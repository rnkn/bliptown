#!/usr/bin/env sh

queuedir=/var/db/msmtp/queue

for mail in "$queuedir"/*.mail; do
	if [ "$mail" = "$queuedir/*.mail" ]; then
		echo "No mail in queue"		
		continue
	fi
	grep -EsH '(^From:|^To:|^Subject:)' "$mail" | sed 's|$queuedir/||'
done
