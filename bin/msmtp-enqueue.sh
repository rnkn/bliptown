#!/usr/bin/env sh

queuedir=/var/db/msmtp/queue
runqueue=/usr/local/www/bliptown/bin/msmtp-runqueue.sh

# Set secure permissions on created directories and files
umask 007

# Create queue directory if necessary
if [ ! -d "$queuedir" ]; then
	mkdir -p "$queuedir" || exit 1
fi

# Create new unique filenames of the form
# mailfile:  ccyy-mm-dd-hh.mm.ss-XXXXXXXX.mail
# msmtpfile: ccyy-mm-dd-hh.mm.ss-XXXXXXXX.msmtp
base="$(date +%Y-%m-%d-%H.%M.%S)-$(openssl rand -hex 4)"
mailfile="$base.mail"
msmtpfile="$base.msmtp"

# Write command line to $msmtpfile
echo "$@" > "$queuedir/$msmtpfile" || exit 1

# Write the mail to $mailfile
cat > "$queuedir/$mailfile" || exit 1

# If mailbox.org is reachable, run the queue immediately.
if nc -z smtp.mailbox.org 465 2>/dev/null; then
	"$runqueue" >/dev/null &
fi

exit 0
