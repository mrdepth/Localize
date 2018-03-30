#!/bin/sh

#  localize.sh
#  Localize
#
#  Created by Artem Shimanski on 29.03.2018.
#  Copyright © 2018 Artem Shimanski. All rights reserved.

args=("$@")
keychain=com.shimanski.localize.${spreadsheet}

while [[ $# -gt 0 ]]
do
key="$1"
case $key in
	-spreadsheet)
	spreadsheet="$2"
	shift
	shift
	;;
	*)
	shift
	;;
esac
done

if [[ $ACTION = clean ]]
then
	if security find-generic-password -l "${keychain}" &> /dev/null
	then
		security delete-generic-password -l "${keychain}"
	fi

else
	${BUILT_PRODUCTS_DIR}/Localize "${args[@]}" -password-keychain "${keychain}"
fi
