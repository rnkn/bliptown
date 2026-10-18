#!/usr/bin/env sh

queuedir=/var/db/msmtp/queue
lockfile="$queuedir/.lock"
maxwait=120

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

# check for empty queuedir
if ! ls "$queuedir"/*.mail 2>/dev/null; then
	echo "No mail in $queuedir"
	exit 0
fi

# wait up to $maxwait seconds for an exclusive lock on the queue;
# the kernel releases it when the subshell exits, so there is no
# lock file to clean up and no stale lock possible.
# The lock is opened with a subshell redirection, not `exec 9>`,
# because /bin/sh marks exec-opened fds close-on-exec and flock
# would fail with EBADF (see the example in flock(1))
(
	flock -w "$maxwait" 100 || {
		cat <<EOF
Cannot use $queuedir: waited $maxwait seconds for the queue lock
to be released, giving up.
EOF
		exit 1
	}

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
) 100> "$lockfile" || exit 1

exit 0
