#!/usr/bin/env sh

queuedir=/var/db/msmtp/queue

# Set secure permissions on created directories and files
umask 007

# Create queue directory if necessary
if [ ! -d "$queuedir" ]; then
	mkdir -p "$queuedir" || exit 1
fi

date=$(date +%Y-%m-%d-%H.%M.%S)

mailfile_tmp=$(mktemp "$queuedir/.mail.$date.XXXXXXXX")
base_tmp=$(basename "$mailfile_tmp")
msmtpfile_tmp="$queuedir/.msmtp.${base_tmp#.mail.}"

trap 'rm -f "$mailfile_tmp" "$msmtpfile_tmp"' EXIT INT QUIT

mailfile="$queuedir/${base_tmp#.mail.}.mail"
msmtpfile="$queuedir/${base_tmp#.mail.}.msmtp"

runqueue=/usr/local/www/bliptown/bin/msmtp-runqueue.sh

# Write the message to the mail tempfile
cat > "$mailfile_tmp" || exit 1

# Write command line to the msmtp tempfile
echo "$@" > "$msmtpfile_tmp" || exit 1

# Rename the tempfiles
mv "$msmtpfile_tmp" "$msmtpfile"
mv "$mailfile_tmp" "$mailfile"

# If mailbox.org is reachable, run the queue immediately.
if nc -z smtp.mailbox.org 465 2>/dev/null; then
	"$runqueue" >/dev/null &
fi

exit 0
