#!/usr/bin/env sh

queuedir=/var/db/msmtp/queue
lockfile="$queuedir/.lock"

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

# take the queue lock without blocking: if it is held, another runner
# is already flushing the queue, so there is nothing to report or do
(
	if ! flock -n 9; then
		exit 0
	fi

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
