#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

chmod u+x $DIR/git-vcn-unstage.sh
cp $DIR/git-vcn-unstage.sh /usr/local/bin/git-vcn-unstage.sh
git config --global alias.unstage '!cd ${GIT_PREFIX:-.} && git-vcn-unstage.sh'

