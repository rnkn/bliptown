#!/bin/ksh

case "$SSH_ORIGINAL_COMMAND" in
	(sftp*)
		exec /usr/libexec/sftp-server
		;;
	(git*)
		exec git-shell -c "$SSH_ORIGINAL_COMMAND"
		;;
	(openrsync*)
		exec openrsync ${SSH_ORIGINAL_COMMAND#openrsync}
		;;
	(rsync*)
		exec openrsync ${SSH_ORIGINAL_COMMAND#rsync}
		;;
	(*)
		/usr/local/www/bliptown/bin/bliptown-shell
		;;
esac
