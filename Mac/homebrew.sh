#!/bin/bash

# Exit on certain errors
set -u

main() {
    # Check arguments
    if (($# > 0)); then
        >&2 echo "Error: expected no arguments"
        >&2 echo "USAGE: ./homebrew.sh"
        exit 1
    fi

    /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    if (($? != 0)); then
        >&2 echo "Homebrew installation failed, exiting"
        exit 1
    fi

    return 0
}

main "$@"
