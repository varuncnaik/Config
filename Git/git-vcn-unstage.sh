#!/bin/bash

# Exit on certain errors
set -u

show_help() {
    >&2 echo "Bad option -$OPTARG...no changes made to index"
    >&2 echo 'Usage: git unstage [-A] [-v] [--] [FILE]...'
    >&2 echo
    >&2 echo '    -A                    unstage all files in the index'
    >&2 echo '    -v                    be verbose'
    >&2 echo
}

no_changes() {
    >&2 echo 'Nothing specified, nothing unstaged.'
    >&2 echo "Maybe you wanted to say 'git unstage -A'?"
}

# TODO: finish this (check status)
unstage_if_no_conflict() {
    local line="$1"
    if [[ -z "$line" ]]; then
        return 1
    fi
    local status="${line:0:2}"
    local file="${line:3}"
    if [[ "$status" == "??" ]]; then
        return 1
    fi
    # TODO: do a single git reset at the end, not one for each file
    git reset HEAD -- "$file" > /dev/null
    return 0
}

# Option globals
opt_all=0
opt_verbosity=0

# Read options into option globals, or exit with status 1 if there's a bad option
read_args() {
    # If we're not in a git repository, then display an error and exit
    git rev-parse --git-dir > /dev/null
    if (($? != 0)); then
        exit 1
    fi

    OPTIND=1
    local opt
    while getopts ":Av" opt; do
        case "$opt" in
        A)  opt_all=1
            ;;
        v)  opt_verbosity=1
            ;;
        ?)  show_help
            exit 1
            ;;
        esac
    done
}

main() {
    read_args "$@"
    shift "$((OPTIND-1))" # Reset in case getopts was used previously in the script

    local lines
    local verbose_msg
    if ((opt_all == 1)); then
        # TODO: change to git status -z or git diff --staged --name-only -z
        lines="$(cd "${GIT_PREFIX:-.}" && git status --porcelain)"
        verbose_msg="git reset"
    else
        if (($# == 0)); then
            no_changes
            exit 1
        fi
        # TODO: change to git status -z or git diff --staged --name-only -z
        lines="$(cd "${GIT_PREFIX:-.}" && git status --porcelain -- "$@")"
        verbose_msg="git reset HEAD -- $@"
    fi

    if ((opt_verbosity == 1)); then
        echo "$verbose_msg"
        echo "Unstaged changes:"
    fi
    local line
    local file_unstaged=0
    while IFS='' read -r line; do
        # TODO: be careful with rename and copy
        unstage_if_no_conflict "$line"
        if (($? == 0)); then
            if ((opt_verbosity == 1)); then
                echo "$line"
            fi
            file_unstaged=1
        fi
    done <<<"$lines"

    if ((file_unstaged == 0)); then
        >&2 echo "No changes made to index."
    fi
}

main "$@"
