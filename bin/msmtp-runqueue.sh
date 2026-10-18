#!/usr/bin/env sh

queuedir=/var/db/msmtp/queue
lockfile="$queuedir/.lock"
maxwait=120

trap 'rm -f $lockfile' EXIT

options=$*

# eat some options that would cause msmtp to return 0 without sendmail mail
case "$options" in 
	(*--help*)
		echo "$0: send mail in $queuedir"
		echo "Options are passed to msmtp"
		exit 0
		;;
	(*--version*)
		echo "$0: unknown version"
		exit 0
		;;
esac

# wait for a lock that another instance has set
wait=0
while [ -e "$lockfile" ] && [ "$wait" -lt "$maxwait" ]; do
	sleep 1
	wait=$((wait + 1))
done
if [ -e "$lockfile" ]; then
	cat <<EOF
Cannot use $queuedir: waited $maxwait seconds for lockfile
$lockfile to vanish, giving up.
If you are sure that no other instance of this script is running, then
delete the lock file.
EOF
	exit 1
fi

# check for empty queuedir
if ! ls "$queuedir"/*.mail 2>/dev/null; then
	echo "No mail in $queuedir"
	exit 0
fi

# lock the $queuedir
touch "$lockfile" || exit 1

# process all mails
for mailfile in "$queuedir"/*.mail; do
	msmtpfile="${mailfile%.mail}.msmtp"
	recipient=$(sed -E 's/^.*-- (.*)$/\1/' "$msmtpfile")
	echo "=> Sending $mailfile to $recipient..."
	if [ ! -f "$msmtpfile" ]; then
		echo "No corresponding file $msmtpfile found"
		echo "FAILED"
		continue
	fi
	if msmtp $options $(cat "$msmtpfile") < "$mailfile"; then
		rm "$mailfile" "$msmtpfile"
		echo "$mailfile sent successfully"
	else
		echo "FAILED"
	fi
done

exit 0
