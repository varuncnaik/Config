#!/bin/bash

# Exit on certain errors
set -u

main() {
    # Check arguments
    if (($# > 0)); then
        >&2 echo "Error: expected no arguments"
        >&2 echo "USAGE: ./generateGitConfig.sh"
        exit 1
    fi

    # Use less as the pager
    git config --global core.pager 'less'
    if (($? != 0)); then
        >&2 echo "git config core.pager failed, exiting"
        exit 1
    fi

    # Simple push - push current branch to a branch of the same name
    git config --global push.default simple
    if (($? != 0)); then
        >&2 echo "git config push.default failed, exiting"
        exit 1
    fi

    return 0
}

main "$@"
