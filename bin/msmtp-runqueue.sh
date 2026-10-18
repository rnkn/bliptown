#!/usr/bin/env sh

queuedir=/var/db/msmtp/queue
lockfile="$queuedir/.lock"
maxwait=120

# eat some options that would cause msmtp to return 0 without sendmail mail
for i; do
	case "$i" in 
		(--help)
			echo "$0: send mail in $queuedir"
			echo "Options are passed to msmtp"
			exit 0
			;;
		(--version)
			echo "$0: unknown version"
			exit 0
			;;
	esac
done

# wait up to $maxwait seconds for an exclusive lock on the queue
(
	flock -w "$maxwait" 9 || {
		cat <<EOF
Cannot use $queuedir: waited $maxwait seconds for the queue lock
to be released, giving up.
EOF
		exit 1
	}

	# process all mails
	for mailfile in "$queuedir"/*.mail; do
        if [ "$mailfile" = "$queuedir/*.mail" ]; then
			echo "No mail in $queuedir"
			continue
        fi

		msmtpfile="${mailfile%.mail}.msmtp"
		recipient=$(sed -E 's/^.*-- (.*)$/\1/' "$msmtpfile")
		echo "=> Sending $mailfile to $recipient..."
		if [ ! -f "$msmtpfile" ]; then
			echo "No corresponding file $msmtpfile found"
			echo "FAILED"
			continue
		fi

		if msmtp "$@" $(cat "$msmtpfile") < "$mailfile"; then
			rm "$mailfile" "$msmtpfile"
			echo "$mailfile sent successfully"
		else
			echo "FAILED"
		fi
	done
) 9> "$lockfile" || exit 1

exit 0
