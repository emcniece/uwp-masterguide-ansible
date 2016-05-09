#!/bin/bash
# Eric McNiece | Feb 22 2016 23:56:12
#
# This script finds all wp-config.php files in the /var/www
# directories, iterates over them, and extracts all of the
# WP_REDIS_DATABASE numbers from the PHP define() declarations.
#
# The var `dbnum` stores the highest found value, and at the
# very end increments by one to return a safe number for any
# other scripts to use as the next redis db number.
#
# reading pipe data creates subshells - watch out for opening and
# closing parens around the while and after the final echo.
#
# A better way to do this would probably be to query redis iteslf.

dbnum=0

find /var/www -name "wp-config.php" | ( while read fname; do
	dump=$(cat "$fname")
	this_dbnum=$(echo $dump | grep -o -P "WP_REDIS_DATABASE', (?:[\d]+)" | grep -o -P "\d+")

	# Debug: uncomment next line!
	# echo $this_dbnum

	if [ $this_dbnum -gt $dbnum ]; then
		dbnum=$this_dbnum
	fi

done

let dbnum++
echo $dbnum )
