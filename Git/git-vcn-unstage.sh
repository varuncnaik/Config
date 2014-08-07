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
    if [ -z "$line" ]; then
        return 1
    fi
    local status=${line:0:2}
    local file=${line:3}
    if [ "$status" == "??" ]; then
        return 1
    fi
    git reset HEAD -- $file > /dev/null
    return 0
}

# Option globals
optAll=0
optVerbosity=0
fileUnstaged=0

# Read options into option globals, or exit with status 1 if there's a bad option
readArgs() {
    local gitDirectory=$(git rev-parse --git-dir 2> /dev/null)
    if [ -z "$gitDirectory" ]; then
        git status       # Display a message saying we're not in a git repository
        exit 1
    fi
    OPTIND=1
    while getopts ":Av" opt; do
        case "$opt" in
        A)  optAll=1
            ;;
        v)  optVerbosity=1
            ;;
        ?)  showHelp
            exit 1
            ;;
        esac
    done
}

main() {
    local lines=""
    local verboseMsg=""
    local status=0
    readArgs "$@"
    shift $(($OPTIND-1)) # Reset in case getopts was used previously in the script
    if ((optAll==1)); then
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
    
    if ((optVerbosity==1)); then
        echo "$verboseMsg"
        echo "Unstaged changes:"
    fi
    while IFS='' read -r line; do
        unstageIfNoConflict "$line"
        status=$?        # return value of the previous function
        if ((status==0)); then
            if ((optVerbosity==1)); then
                echo "$line"
            fi
            fileUnstaged=1
        fi
    done <<<"$lines"
    
    if ((fileUnstaged==0)); then
        echo "No changes made to index."
    fi
}

main "$@"

