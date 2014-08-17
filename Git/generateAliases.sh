#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

chmod u+x $DIR/git-vcn-unstage.sh
cp $DIR/git-vcn-unstage.sh /usr/local/bin/git-vcn-unstage.sh
git config --global alias.unstage '!git-vcn-unstage.sh'
git config --global alias.word-diff 'diff --word-diff-regex="[^[:space:](),]+"'
git config --global color.ui always
git config --global push.default simple

