#!/bin/bash

# Exit on certain errors
set -u

# Index lock file global (can be absolute path or relative path)
index_lock_file=''
# Ref lock file globals (can be absolute path or relative path)
head_lock_file=''
ref_lock_file=''

# Option globals
opt_merge=0
opt_unstage=0
opt_verbosity=0

# Signal handler to remove lock files.
# $1: signal number
cleanup() {
    # See tempfile.c:remove_tempfiles()
    if [[ -n "$ref_lock_file" ]]; then
        rm -- "$ref_lock_file" > /dev/null 2>&1
    fi
    if [[ -n "$head_lock_file" ]]; then
        rm -- "$head_lock_file" > /dev/null 2>&1
    fi
    if [[ -n "$index_lock_file" ]]; then
        rm -- "$index_lock_file" > /dev/null 2>&1
    fi

    # Exit code depends on signal number
    exit "$((128+$1))"
}

# Near-atomically creates index lock file and sets index_lock_file, or displays
# an error and exits.
# $1: git directory
create_index_lock_file() {
    # If GIT_INDEX_FILE is unset, then use index.lock, otherwise use
    # GIT_INDEX_FILE and append .lock
    # See `man git` .. "ENVIRONMENT VARIABLES" .. "GIT_INDEX_FILE"
    local lock_file
    lock_file="${GIT_INDEX_FILE-"$1/index"}.lock"

    # Atomically create the lock file
    local lock_status
    (set -o noclobber; { > "$lock_file" ; } > /dev/null 2>&1)
    lock_status=$?

    # We can't create the lock file and set index_lock_file atomically (there
    # could be a signal), but the only damage is that the lock file lingers.
    index_lock_file="$lock_file"

    if ((lock_status != 0)); then
        # Print an error message, then exit. There's a race condition here too
        # (the lock file could be removed before the git command), but it's
        # probably very rare, and the only damage is an inaccurate error
        # message.
        git add
        exit 1
    fi
}

# Near-atomically creates head lock file and sets head_lock_file, or displays an
# error and exits.
# $1: git directory
create_head_lock_file() {
    local lock_file
    lock_file="$1/HEAD.lock"

    # Atomically create the lock file
    local lock_status
    (set -o noclobber; { > "$lock_file" ; } > /dev/null 2>&1)
    lock_status=$?

    # We can't create the lock file and set head_lock_file atomically (there
    # could be a signal), but the only damage is that the lock file lingers.
    head_lock_file="$lock_file"

    if ((lock_status != 0)); then
        # Print an error message, then exit. Creates a new empty reflog entry,
        # and prints an inaccurate message on an unborn branch. There's a race
        # condition here too (the lock file could be removed before the git
        # command), but it's probably very rare, and the only damage is a
        # missing error message and a new empty reflog entry.
        git update-ref HEAD HEAD
        remove_index_lock_file
        exit 1
    fi
}

# Near-atomically creates ref lock file and sets ref_lock_file, or displays an
# error and exits.
# $1: git directory
# $2: full ref name
create_ref_lock_file() {
    local lock_file
    lock_file="$1/$2.lock"

    # Atomically create the lock file
    local lock_status
    (set -o noclobber; { > "$lock_file" ; } > /dev/null 2>&1)
    lock_status=$?

    # We can't create the lock file and set ref_lock_file atomically (there
    # could be a signal), but the only damage is that the lock file lingers.
    ref_lock_file="$lock_file"

    if ((lock_status != 0)); then
        # Print an error message, then exit. Creates a new empty reflog entry,
        # and prints an inaccurate message on an unborn branch. There's a race
        # condition here too (the lock file could be removed before the git
        # command), but it's probably very rare, and the only damage is a
        # missing error message and a new empty reflog entry.
        git update-ref "$2" "$2" "$2"
        remove_head_lock_file
        remove_index_lock_file
        exit 1
    fi
}

# Near-atomically deletes index lock file and unsets index_lock_file.
remove_index_lock_file() {
    local lock_file
    lock_file="$index_lock_file"

    # We can't delete the lock file and unset index_lock_file atomically (there
    # could be a signal), but the only damage is that the lock file lingers.
    index_lock_file=''

    # See tempfile.c:remove_tempfiles()
    rm -- "$lock_file"
}

# Near-atomically deletes head lock file and unsets head_lock_file.
remove_head_lock_file() {
    local lock_file
    lock_file="$head_lock_file"

    # We can't delete the lock file and unset head_lock_file atomically (there
    # could be a signal), but the only damage is that the lock file lingers.
    head_lock_file=''

    # See tempfile.c:remove_tempfiles()
    rm -- "$lock_file"
}

# Near-atomically deletes ref lock file and unsets ref_lock_file.
remove_ref_lock_file_if_exists() {
    if [[ -z "$ref_lock_file" ]]; then
        return 0
    fi

    local lock_file
    lock_file="$ref_lock_file"

    # We can't delete the lock file and unset ref_lock_file atomically (there
    # could be a signal), but the only damage is that the lock file lingers.
    ref_lock_file=''

    # See tempfile.c:remove_tempfiles()
    rm -- "$lock_file"
}

# Prints a "help" message.
# $1: the bad option
show_help() {
    >&2 echo "Bad option -$1...nothing uncommitted"
    >&2 echo 'Usage: git uncommit [-m] [-u] [-v]'
    >&2 echo
    >&2 echo '    -m                    uncommit a merge commit'
    >&2 echo '    -u                    unstage all files, in addition to uncommiting'
    >&2 echo '    -v                    be verbose'
    >&2 echo
}

# Reads options into option globals, or exits with status 1 if there's a bad
# option. Changes the shell variables OPTARG and OPTIND.
read_args() {
    if ((OPTIND != 1)); then
        >&2 echo "BUG: OPTIND is $OPTIND"' != 1'
        exit 1
    fi

    local opt
    while getopts ":muv" opt; do
        case "$opt" in
        m)  opt_merge=1
            ;;
        u)  opt_unstage=1
            ;;
        v)  opt_verbosity=1
            ;;
        ?)  show_help "$OPTARG"
            exit 1
            ;;
        esac
    done
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
    # Assumption: the path and contents of the git dir, the path and contents of
    # the index file, the path of the working tree, the path of the current
    # directory, and the contents of the git executable are not changed by
    # another process throughout program execution
    # To deal with trailing newlines, add an extra character at the end...
    local git_dir
    git_dir="$(git rev-parse --git-dir && echo 'x')"
    if (($? != 0)); then
        exit 1
    fi
    # ... and then remove the extra character
    git_dir="${git_dir%$'\nx'}"

    # Read option arguments, and then shift past them
    read_args "$@"
    shift "$((OPTIND-1))"

    if (($# > 0)); then
        >&2 echo 'Error: non-option arguments found'
        exit 1
    fi

    # Lock necessary files. We need to lock the index in addition to refs
    # because we want the index to be empty when we move refs later.
    local head_branch
    local head_branch_status
    create_index_lock_file "$git_dir"
    create_head_lock_file "$git_dir"
    head_branch="$(git symbolic-ref --quiet HEAD)"
    head_branch_status=$?
    if ((head_branch_status == 0)); then
        # HEAD is pointing to a branch
        create_ref_lock_file "$git_dir" "$head_branch"
    elif ((head_branch_status != 1)); then
        >&2 echo 'BUG: git symbolic-ref failed'
        remove_head_lock_file
        remove_index_lock_file
        exit 1
    fi

    # Determine HEAD. If HEAD is invalid (we are on an unborn branch), then exit
    # immediately.
    local head_commit
    head_commit="$(git rev-parse --revs-only HEAD)"
    if (($? != 0)); then
        >&2 echo 'BUG: git rev-parse HEAD failed'
        remove_ref_lock_file_if_exists
        remove_head_lock_file
        remove_index_lock_file
        exit 1
    fi
    if [[ -z "$head_commit" ]]; then
        >&2 echo 'Error: commit for HEAD not found'
        remove_ref_lock_file_if_exists
        remove_head_lock_file
        remove_index_lock_file
        exit 1
    fi

    # Determine remote branch name and commit, if it exists
    local remote_branch
    local remote_branch_commit
    if ((head_branch_status == 0)); then
        # Append an extra character 'x' to prevent Bash from truncating newlines
        # in a command substitution.
        remote_branch="$(git for-each-ref --format='%(upstream:short)x' "$head_branch")"
        if [[ "$remote_branch" == '' ]]; then
            >&2 echo "BUG: git for-each-ref '$head_branch' failed"
            remove_ref_lock_file_if_exists
            remove_head_lock_file
            remove_index_lock_file
            exit 1
        elif [[ "$remote_branch" == 'x' ]]; then
            # Missing remote branch
            remote_branch=""
            remote_branch_commit=""
        else
            remote_branch="${remote_branch%x}"
            remote_branch_commit="$(git rev-parse --revs-only "$remote_branch")"
            if (($? != 0)); then
                >&2 echo "BUG: git rev-parse '$remote_branch' failed"
                remove_ref_lock_file_if_exists
                remove_head_lock_file
                remove_index_lock_file
                exit 1
            fi
            if [[ -z "$remote_branch_commit" ]]; then
                >&2 echo "Error: commit for '$remote_branch' not found"
                remove_ref_lock_file_if_exists
                remove_head_lock_file
                remove_index_lock_file
                exit 1
            fi
        fi
    else
        # Detached HEAD
        remote_branch=""
        remote_branch_commit=""
    fi

    if [[ -f "$git_dir/MERGE_HEAD" \
       || -d "$git_dir/rebase-apply" \
       || -d "$git_dir/rebase-merge" \
       || -f "$git_dir/CHERRY_PICK_HEAD" \
       || -f "$git_dir/BISECT_LOG" \
       || -f "$git_dir/REVERT_HEAD" \
       ]]; then
        >&2 echo "Error: possible conflict detected, run 'git status'"
        remove_ref_lock_file_if_exists
        remove_head_lock_file
        remove_index_lock_file
        exit 1
    fi

    local first_parent
    first_parent="$(git rev-parse --revs-only "${head_commit}^1")"
    if (($? != 0)); then
        >&2 echo 'BUG: git rev-parse HEAD~ failed'
        remove_ref_lock_file_if_exists
        remove_head_lock_file
        remove_index_lock_file
        exit 1
    fi
    if [[ -z "$first_parent" ]]; then
        >&2 echo 'Error: commit for HEAD~ not found'
        remove_ref_lock_file_if_exists
        remove_head_lock_file
        remove_index_lock_file
        exit 1
    fi

    if ((opt_merge == 0)); then
        local second_parent
        second_parent="$(git rev-parse --revs-only "${head_commit}^2")"
        if (($? != 0)); then
            >&2 echo 'BUG: git rev-parse HEAD^2 failed'
            remove_ref_lock_file_if_exists
            remove_head_lock_file
            remove_index_lock_file
            exit 1
        fi
        if [[ -n "$second_parent" ]]; then
            >&2 echo "Error: HEAD is a merge commit, run 'git reset' or re-run with -m"
            remove_ref_lock_file_if_exists
            remove_head_lock_file
            remove_index_lock_file
            exit 1
        fi
    fi

    if [[ -n "$remote_branch_commit" ]]; then
        local ancestor_status
        git merge-base --is-ancestor "$remote_branch_commit" "${head_commit}^1"
        ancestor_status=$?
        if ((ancestor_status == 1)); then
            >&2 echo "Error: remote branch $remote_branch is not an ancestor of HEAD~, run 'git reset'"
            remove_ref_lock_file_if_exists
            remove_head_lock_file
            remove_index_lock_file
            exit 1
        elif ((ancestor_status != 0)); then
            >&2 echo 'BUG: git merge-base failed'
            remove_ref_lock_file_if_exists
            remove_head_lock_file
            remove_index_lock_file
            exit 1
        fi
    fi

    # Remove ref and head lock files, so `git reset` can run
    remove_ref_lock_file_if_exists
    remove_head_lock_file

    if ((opt_unstage == 0)); then
        GIT_REFLOG_ACTION='uncommit' git reset --soft "$first_parent"
        if (($? != 0)); then
            >&2 echo 'BUG: git reset --soft failed'
            remove_index_lock_file
            exit 1
        fi
        remove_index_lock_file
    else
        remove_index_lock_file
        GIT_REFLOG_ACTION='uncommit' git reset --mixed "$first_parent"
        if (($? != 0)); then
            >&2 echo 'BUG: git reset --mixed failed'
            exit 1
        fi
    fi

    return 0
}

main "$@"
