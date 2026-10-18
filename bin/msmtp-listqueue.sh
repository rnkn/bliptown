#!/usr/bin/env sh

queuedir=/var/db/msmtp/queue

for i in "$queuedir"/*.mail; do
	(grep -EsH '(^From:|^To:|^Subject:)' "$i" | sed 's|$queuedir/||') || echo "No mail in queue";
done
