#!/bin/bash

# Exit on certain errors
set -u

# Global constants
readonly DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly BIN_DIR='/usr/local/bin'

main() {
    # Check arguments
    if (($# > 0)); then
        >&2 echo "Error: expected no arguments"
        >&2 echo "USAGE: ./generateAliases.sh"
        exit 1
    fi

    # git unstage
    if [[ -e "$BIN_DIR/git-vcn-unstage.sh" && ! -f "$BIN_DIR/git-vcn-unstage.sh" ]]; then
        >&2 echo "$BIN_DIR/git-vcn-unstage.sh exists and is not a regular file, exiting"
        exit 1
    fi
    cp "$DIR/git-vcn-unstage.sh" "$BIN_DIR/git-vcn-unstage.sh"
    if (($? != 0)); then
        >&2 echo "cp failed, exiting"
        exit 1
    fi
    chmod u+x "$BIN_DIR/git-vcn-unstage.sh"
    if (($? != 0)); then
        >&2 echo "chmod failed, exiting"
        exit 1
    fi
    git config --global alias.unstage '!git-vcn-unstage.sh'
    if (($? != 0)); then
        >&2 echo "git config alias.unstage failed, exiting"
        exit 1
    fi

    # git uncommit
    if [[ -e "$BIN_DIR/git-vcn-uncommit.sh" && ! -f "$BIN_DIR/git-vcn-uncommit.sh" ]]; then
        >&2 echo "$BIN_DIR/git-vcn-uncommit.sh exists and is not a regular file, exiting"
        exit 1
    fi
    cp "$DIR/git-vcn-uncommit.sh" "$BIN_DIR/git-vcn-uncommit.sh"
    if (($? != 0)); then
        >&2 echo "cp failed, exiting"
        exit 1
    fi
    chmod u+x "$BIN_DIR/git-vcn-uncommit.sh"
    if (($? != 0)); then
        >&2 echo "chmod failed, exiting"
        exit 1
    fi
    git config --global alias.uncommit '!git-vcn-uncommit.sh'
    if (($? != 0)); then
        >&2 echo "git config alias.uncommit failed, exiting"
        exit 1
    fi

    return 0
}

main "$@"
