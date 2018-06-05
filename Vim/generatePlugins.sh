#!/bin/bash

# Exit on certain errors
set -u

main() {
    # Check arguments
    if (($# > 0)); then
        >&2 echo "Error: expected no arguments"
        >&2 echo "USAGE: ./generatePlugins.sh"
        exit 1
    fi

    if [[ ! -f "$HOME/.vimrc" ]]; then
        >&2 echo "Could not find vimrc, exiting"
        exit 1
    fi
    git --version > /dev/null 2>&1
    if (($? != 0)); then
        >&2 echo "git is not installed, exiting"
        exit 1
    fi

    echo "Installing Pathogen..."
    mkdir -p ~/.vim/autoload ~/.vim/bundle && \
        curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
    if (($? != 0)); then
        >&2 echo "Pathogen installation failed, exiting"
        exit 1
    fi

    echo >> "$HOME/.vimrc"
    echo '" Pathogen' >> "$HOME/.vimrc"
    echo 'execute pathogen#infect()' >> "$HOME/.vimrc"

    if [[ -d "$HOME/.vim/bundle/rust.vim" ]]; then
        echo "rust.vim already installed, skipping..."
    else
        git clone --depth=1 https://github.com/rust-lang/rust.vim.git "$HOME/.vim/bundle/rust.vim"
        if (($? != 0)); then
            >&2 echo "Clone of rust.vim failed, exiting"
            exit 1
        fi
    fi

    return 0
}

main "$@"
