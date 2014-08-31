#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Aliases
chmod u+x $DIR/git-vcn-unstage.sh
cp $DIR/git-vcn-unstage.sh /usr/local/bin/git-vcn-unstage.sh
git config --global alias.unstage '!git-vcn-unstage.sh'
git config --global alias.word-diff 'diff --word-diff-regex="[^[:space:](),]+"'

# Always show color
git config --global color.ui always

# Simple push - push current branch to a branch of the same name
git config --global push.default simple

