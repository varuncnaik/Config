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
    git reset HEAD -- $file > /dev/null
}

OPTIND=1 # Reset in case getopts was used previously in the script

ALL=0
VERBOSITY=0

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

if ((ALL == 1)); then
    if ((VERBOSITY==1)); then
        echo "git reset"
        echo "Unstaged changes:"
    fi
    lines=$(cd ${GIT_PREFIX:-.} && git status --porcelain)
    if [ -z "$lines" ]; then
        echo "No files unstaged."
    else
        while read line; do
            unstageIfNoConflict "$line"
            if ((VERBOSITY==1)); then
                echo "$line"
            fi
        done <<<"$lines"
    fi

else
    if [ -z "$*" ]; then
        noChanges
    else
        if ((VERBOSITY==1)); then
            echo "git reset HEAD -- $*"
            echo "Unstaged changes:"
        fi
        lines=$(cd ${GIT_PREFIX:-.} && git status --porcelain -- $*)
        if [ -z "$lines" ]; then
            echo "No files unstaged."
        else
            while read line; do
                echo "asdf"
                unstageIfNoConflict "$line"
                if ((VERBOSITY==1)); then
                    echo "$line"
                fi
            done <<<"$lines"
        fi
    fi
fi

