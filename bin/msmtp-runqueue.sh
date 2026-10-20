#!/usr/bin/env sh

queuedir=/var/db/msmtp/queue
lockfile="$queuedir/.lock"

# log to stdout and to syslogd's mail facility
log() {
	echo "$*"
	logger -t msmtp-runqueue -p mail.info "$*"
}

warn() {
	echo "$*"
	logger -t msmtp-runqueue -p mail.warning "$*"
}

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
			exit 0
        fi

		msmtpfile="${mailfile%.mail}.msmtp"
		if [ ! -f "$msmtpfile" ]; then
			warn "No corresponding file $msmtpfile found"
			warn "FAILED: $mailfile"
			continue
		fi

		recipient=$(sed -E 's/^.*-- (.*)$/\1/' "$msmtpfile")
		log "=> Sending $mailfile to $recipient..."
		if msmtp --syslog "$@" $(cat "$msmtpfile") < "$mailfile"; then
			rm "$mailfile" "$msmtpfile"
			log "$mailfile sent successfully"
		else
			warn "FAILED: $mailfile to $recipient"
		fi
	done
) 9> "$lockfile" || exit 1

exit 0
