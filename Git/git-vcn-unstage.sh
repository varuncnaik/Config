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

# TODO: 'git status --porcelain' to check for branch/stash merge conflicts
if ((ALL == 1)); then
    if ((VERBOSITY==1)); then
        echo "git reset"
        git reset
    else
        git reset > /dev/null
    fi
else
    if [ -z "$*" ]; then
        noChanges
    else
        if ((VERBOSITY==1)); then
            echo "git reset HEAD -- $*"
            git reset HEAD -- $*
        else
            git reset HEAD -- $* > /dev/null
        fi
    fi
fi

