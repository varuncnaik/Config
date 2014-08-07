#!/bin/bash

showHelp() {
    echo "Bad option -$OPTARG...no changes made to index"
    echo 'Usage: git unstage [-A] [-v] [--] [FILE]...'
    echo
    echo '    -A                    unstage all files in the index'
    echo '    -v                    be verbose'
    echo
}

noChanges() {
    echo 'Nothing specified, nothing unstaged.'
    echo "Maybe you wanted to say 'git unstage -A'?"
}

# TODO: finish this (check status)
unstageIfNoConflict() {
    local line=$1
    local status=${line:0:2}
    local file=${line:3}
    if [ "$status" == "??" ]; then
        return 1
    fi
    git reset HEAD -- $file > /dev/null
    return 0
}

OPTIND=1 # Reset in case getopts was used previously in the script

# Boolean globals
ALL=0
VERBOSITY=0
FILE_UNSTAGED=0

while getopts ":Av" opt; do
    case "$opt" in
    A)  ALL=1
        ;;
    v)  VERBOSITY=1
        ;;
    ?)  showHelp
        exit 1
        ;;
    esac
done

shift "$((OPTIND-1))"

if ((ALL==1)); then
    lines=$(cd ${GIT_PREFIX:-.} && git status --porcelain)
    verboseMsg="git reset"
else
    if [ -z "$*" ]; then
        noChanges
        exit 1
    fi
    lines=$(cd ${GIT_PREFIX:-.} && git status --porcelain -- $*)
    verboseMsg="git reset HEAD -- $*"
fi

if ((VERBOSITY==1)); then
    echo "$verboseMsg"
    echo "Unstaged changes:"
fi
while IFS='' read -r line; do
    unstageIfNoConflict "$line"
    status=$?        # return value of the previous function
    if ((status==0)); then
        if ((VERBOSITY==1)); then
            echo "$line"
        fi
        FILE_UNSTAGED=1
    fi
done <<<"$lines"
if ((FILE_UNSTAGED==0)); then
    echo "No changes made to index."
fi

