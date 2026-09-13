#!/bin/sh

PAGER=cat perldoc lib/Bliptown.pm
echo

find -f lib/ script/ templates/ t/ public/ -type f ! -name '*~' ! -name '*_' ! -path 'public/defaults/*' | while read -r file
do
	echo "## File: $file ##"
	echo
	echo '```'
	cat "$file"
	echo '```'
	echo
done
