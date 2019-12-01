#!/bin/bash

# Exit on certain errors
set -u

# Signal handler to remove lock files.
# $1: signal number
cleanup() {
    # Exit code depends on signal number
    exit "$((128+$1))"
}

main() {
    # See sigchain.c:sigchain_push_common()
    trap 'cleanup '"$(kill -l INT)" INT
    trap 'cleanup '"$(kill -l HUP)" HUP
    trap 'cleanup '"$(kill -l TERM)" TERM
    trap 'cleanup '"$(kill -l QUIT)" QUIT
    trap 'cleanup '"$(kill -l PIPE)" PIPE

    # If we're in a git repository, then get the path to the git directory.
    # Otherwise, display an error and exit.
    # Assumption: the path and contents of the git dir, the path of the working
    # tree, the path of the current directory, and the contents of the git
    # executable are not changed by another process throughout program execution
    # To deal with trailing newlines, add an extra character at the end...
    local git_dir
    git_dir="$(git rev-parse --git-dir && echo 'x')"
    if (($? != 0)); then
        exit 1
    fi
    # ... and then remove the extra character
    git_dir="${git_dir%$'\nx'}"

    if (($# != 1)); then
        >&2 echo 'Error: wrong number of arguments'
        exit 1
    fi

    if [[ "$1" != *":"* ]]; then
        >&2 echo 'Error: could not parse src:dst'
        exit 1
    fi

    local src
    local dst
    src="${1%%:*}"
    dst="${1##*:}"

    if ((${#src} + ${#dst} + 1 < ${#1})); then
        >&2 echo 'Error: could not parse src:dst'
        exit 1
    fi

    local src_commit
    src_commit="$(git rev-parse --revs-only "$src^{object}")"
    if (($? != 0)); then
        >&2 echo "BUG: git rev-parse '$src' failed"
        exit 1
    fi
    if [[ -z "$src_commit" ]]; then
        >&2 echo "Error: source name '$src' does not dereference to a commit"
        exit 1
    fi
    local object_type
    object_type="$(git cat-file -t "$src_commit")"
    if (($? != 0)); then
        >&2 echo "BUG: git cat-file '$src_commit' failed"
        exit 1
    fi
    if [[ "$object_type" == 'blob' || "$object_type" == 'tree' ]]; then
        >&2 echo "Error: expected a commit, but source name '$src' dereferences to a $object_type"
        exit 1
    elif [[ "$object_type" == 'tag' ]]; then
        src_commit="$(git rev-parse --revs-only "$src_commit^{commit}")"
        if (($? != 0)); then
            >&2 echo "BUG: git rev-parse '$src^{commit}' failed"
            exit 1
        fi
    elif [[ "$object_type" != 'commit' ]]; then
        >&2 echo "Error: source name '$src' has an unknown object type $object_type"
        exit 1
    fi

    local dst_ref
    dst_ref="refs/heads/$dst"

    # Check for invalid branch names (including a trailing slash)
    git check-ref-format "$dst_ref"
    if (($? != 0)); then
        >&2 echo "Error: destination name '$dst' is an invalid branch name"
        exit 1
    fi

    local dst_ref_foreach
    dst_ref_foreach="$(git for-each-ref --format='x' -- "$dst_ref/")"
    if (($? != 0)); then
        >&2 echo "BUG: git for-each-ref '$dst_ref/' failed"
        exit 1
    elif [[ "$dst_ref_foreach" != '' ]]; then
        >&2 echo "Error: destination name '$dst' is a prefix of a longer branch name"
        exit 1
    fi

    dst_ref_foreach="$(git for-each-ref --format='x' -- "$dst_ref")"
    if (($? != 0)); then
        >&2 echo "BUG: git for-each-ref '$dst_ref' failed"
        exit 1
    elif [[ "$dst_ref_foreach" == '' ]]; then
        local dst_commit
        # I could perform better error handling here for blobs and trees, but I'm lazy
        dst_commit="$(git rev-parse --revs-only "$dst^{commit}")"
        if (($? != 0)); then
            >&2 echo "BUG: git rev-parse '$dst' failed"
        fi
        if [[ -z "$dst_commit" ]]; then
            >&2 echo "Error: destination branch '$dst' does not exist"
        else
            >&2 echo "Error: destination name '$dst' dereferences to a commit, but it is not a branch"
        fi
        exit 1
    elif [[ "$dst_ref_foreach" != 'x' ]]; then
        >&2 echo "BUG: multiple dst refs found for '$dst_ref'"
        exit 1
    fi

    local dst_commit
    dst_commit="$(git rev-parse --revs-only "$dst_ref")"
    if [[ "$src_commit" == "$dst_commit" ]]; then
        echo "Destination branch '$dst' is already up to date."
        return 0
    fi

    git merge-base --is-ancestor -- "$dst_ref" "$src_commit"
    ancestor_status=$?
    if ((ancestor_status == 1)); then
        >&2 echo "Error: destination branch '$dst' is not an ancestor of source commit '$src'"
        exit 1
    elif ((ancestor_status != 0)); then
        >&2 echo 'BUG: git merge-base failed'
        exit 1
    fi

    local head_branch
    local head_branch_status
    head_branch="$(git symbolic-ref -q HEAD)"
    head_branch_status=$?
    if ((head_branch_status == 0)); then
        if [[ "$head_branch" == "$dst_ref" ]]; then
            >&2 echo "Error: destination branch '$dst' is currently checked out"
            exit 1
        fi
    elif ((head_branch_status != 1)); then
        >&2 echo 'BUG: git symbolic-ref failed'
        exit 1
    fi

    # Current approach:
    # - Race condition: $dst_ref might be removed
    # - Race condition: $dst_ref might be updated to another ancestor of $src_commit
    # `git branch -f "$dst_ref" "$src_commit"`:
    # - Race condition: $dst_ref might be removed
    # - Race condition: $dst_ref might be updated
    # - No control over reflog message
    # - One ref update per command
    # `git update-ref -m "ff $1: fast-forward" "$dst_ref" "$src_commit" "$dst_commit"`:
    # - Race condition: HEAD might be updated to point to $dst_ref
    # - One ref update per command
    GIT_REFLOG_ACTION="ff $1" git fetch --quiet . "${src_commit}:${dst_ref}"
    if (($? != 0)); then
        >&2 echo 'BUG: git fetch . failed'
        exit 1
    fi

    local src_abbrev
    src_abbrev="$(git rev-parse --short "$src_commit")"
    local dst_abbrev
    dst_abbrev="$(git rev-parse --short "$dst_commit")"
    echo "Updating $dst_abbrev..$src_abbrev"
    echo "Fast-forward $dst"
    git --no-pager diff --stat --summary "$dst_commit" "$src_commit" --

    return 0
}

main "$@"
