#!/bin/bash

# Exit on certain errors
set -u

# Global constants
readonly DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

main() {
    # Check arguments
    if (($# > 0)); then
        >&2 echo "Error: expected no arguments"
        >&2 echo "USAGE: ./generateVimrc.sh"
        exit 1
    fi

    # Copy vimrc
    if [[ -e "$HOME/.vimrc" || -h "$HOME/.vimrc" ]]; then
        >&2 echo "$HOME/.vimrc exists, exiting"
        exit 1
    fi
    cp "$DIR/vimrc" "$HOME/.vimrc"
    if (($? != 0)); then
        >&2 echo "cp failed, exiting"
        exit 1
    fi

    return 0
}

main "$@"
