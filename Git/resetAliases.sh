#!/bin/bash

# Exit on certain errors
set -u

# Global constants
readonly BIN_DIR='/usr/local/bin'

main() {
    # Check arguments
    if (($# > 0)); then
        >&2 echo "Error: expected no arguments"
        >&2 echo "USAGE: ./resetAliases.sh"
        exit 1
    fi

    # Make sure config file is readable
    git config --global --name-only -l > /dev/null 2>&1
    if (($? != 0)); then
        echo "git config -l failed, exiting"
        exit 1
    fi

    # git unstage
    local unstage
    local unstage_status
    unstage="$(git config --global alias.unstage)"
    unstage_status=$?
    if [[ ! -z "$unstage" ]]; then
        if ((unstage_status != 0)); then
            echo "git config alias.unstage failed, exiting"
            exit 1
        fi
        git config --global --unset alias.unstage
        if (($? != 0)); then
            echo "git config --unset alias.unstage failed, exiting"
            exit 1
        fi
    fi
    rm -rf "$BIN_DIR/git-vcn-unstage.sh"
    if (($? != 0)); then
        echo "rm failed, exiting"
        exit 1
    fi

    # Remove alias section, if necessary
    local aliases
    aliases="$(git config --global --name-only --get-regexp '^alias\.')"
    if [[ -z "$aliases" ]]; then
        # Add a dummy value to avoid error if section doesn't exist
        git config --global alias.tmp tmp
        if (($? != 0)); then
            echo "git config alias.tmp failed, exiting"
            exit 1
        fi
        git config --global --remove-section alias
        if (($? != 0)); then
            echo "git config --remove-section alias failed, exiting"
            exit 1
        fi
    fi

    return 0
}

main "$@"
