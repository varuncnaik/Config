#!/bin/bash

# Exit on certain errors
set -u

# Global constants
readonly DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

main() {
    # Check arguments
    if (($# > 0)); then
        >&2 echo "Error: expected no arguments"
        >&2 echo "USAGE: ./generateBashProfile.sh"
        exit 1
    fi

    # Copy bash_profile
    if [[ -e "$HOME/.bash_profile" || -h "$HOME/.bash_profile" ]]; then
        >&2 echo "$HOME/.bash_profile exists, exiting"
        exit 1
    fi
    cp "$DIR/bash_profile" "$HOME/.bash_profile"
    if (($? != 0)); then
        >&2 echo "cp failed, exiting"
        exit 1
    fi

    echo 'Run `source ~/.bash_profile` for the changes to take effect'
    return 0
}

main "$@"
