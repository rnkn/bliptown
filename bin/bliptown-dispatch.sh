#!/bin/ksh

case "$SSH_ORIGINAL_COMMAND" in
	(sftp*)
		exec /usr/libexec/sftp-server
		;;
	(git*)
		exec git-shell -c "$SSH_ORIGINAL_COMMAND"
		;;
	(rsync*)
		exec rsync ${SSH_ORIGINAL_COMMAND#rsync}
		;;
	(*)
		/usr/local/www/bliptown/bin/bliptown-shell
		;;
esac
