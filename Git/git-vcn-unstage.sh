#!/bin/sh

showHelp() {
	echo 'Bad option...no changes made to index'
	echo 'Usage: git unstage [-A] [-v] [--] [FILE]...'
}

OPTIND=1 # Reset in case getopts was used previously in the script

ALL=0
VERBOSITY=0

while getopts ":Av" OPT; do
	case "$OPT" in
	A)	ALL=1
		;;
	v)	VERBOSITY=1
		;;
	?)	showHelp
		exit 1
		;;
	esac
done

shift "$((OPTIND-1))"

if ((ALL == 1))
then
	if ((VERBOSITY==1))
	then
		echo "git reset HEAD"
		git reset HEAD
	else
		git reset HEAD > /dev/null
	fi
else
	if ((VERBOSITY==1))
	then
		echo "git reset HEAD -- $*"
		git reset HEAD -- $*
	else
		git reset HEAD -- $* > /dev/null
	fi
fi

