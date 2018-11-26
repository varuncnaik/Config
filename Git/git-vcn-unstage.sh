#!/bin/bash

# Exit on certain errors
set -u

# Lock file global (can be absolute path or relative path)
lock_file=''

# Option globals
opt_all=0
opt_verbosity=0

# Signal handler to remove the lock file.
# $1: signal number
cleanup() {
    # See tempfile.c:remove_tempfiles
    if [[ -n "$lock_file" ]]; then
        rm -- "$lock_file" > /dev/null 2>&1
    fi

    # Exit code depends on signal number
    exit "$((128+$1))"
}

# Near-atomically creates lock file and sets lock_file, or displays an error and
# exits.
# $1: git directory
create_lock_file() {
    # If GIT_INDEX_FILE is unset, then use index.lock, otherwise use
    # GIT_INDEX_FILE and append .lock
    # See `man git` .. "ENVIRONMENT VARIABLES" .. "GIT_INDEX_FILE"
    local local_lock_file
    local_lock_file="${GIT_INDEX_FILE-"$1/index"}.lock"

    # Atomically create the lock file
    local lock_status
    (set -o noclobber; { > "$local_lock_file" ; } > /dev/null 2>&1)
    lock_status=$?

    # We can't create the lock file and set lock_file atomically (there could be
    # a signal), but the only damage is that the lock file lingers.
    lock_file="$local_lock_file"

    if ((lock_status != 0)); then
        # Print an error message, then exit. There's a race condition here too
        # (the lock file could be removed before the git command), but it's
        # probably very rare, and the only damage is an inaccurate error
        # message.
        git add
        exit 1
    fi

    return 0
}

# Near-atomically deletes lock and unsets lock_file.
remove_lock_file() {
    local local_lock_file
    local_lock_file="$lock_file"

    # We can't delete the lock file and unset lock_file atomically (there could
    # be a signal), but the only damage is that the lock file lingers.
    lock_file=''

    # See tempfile.c:remove_tempfiles
    rm -- "$local_lock_file"
}

# Prints a "help" message.
show_help() {
    >&2 echo "Bad option -$OPTARG...no changes made to index"
    >&2 echo 'Usage: git unstage [-A] [-v] [--] [FILE]...'
    >&2 echo
    >&2 echo '    -A                    unstage all files in the index'
    >&2 echo '    -v                    be verbose'
    >&2 echo
}

# Prints an error message for when there are no arguments specified.
no_arguments() {
    # Similar error message as `git add`
    >&2 echo 'Nothing specified, nothing unstaged.'
    >&2 echo "Maybe you wanted to say 'git unstage -A'?"
}

# Returns 1 if any file argument is not staged. Runs in a subshell because a
# signal could occur after the initial cd.
# Current approach:
# - Works, but creating a subshell is inefficient
# Don't create a subshell, but cd and change cleanup() to compare pwd:
# - Need to cd back in check_file_arguments() and cleanup()
# Don't create a subshell, but cd and require lock_file to be an absolute path:
# - Need to cd back in check_file_arguments()
# - `git rev-parse` does not provide index file as absolute path
# - Difficult to write portable code that converts relative path to absolute
# Don't create a subshell, and run `git diff --relative ...`:
# - Omits changes outside working directory
# Don't create a subshell, and prepend GIT_PREFIX to each file:
# - Difficult to deal with globbing
check_file_arguments() (
    cd -- "${GIT_PREFIX:-.}"
    if (($? != 0)); then
        return 1
    fi

    # Current approach:
    # - Works, but calls `git diff` once for every file argument
    # `git ls-files --error-unmatch <OPTIONS> -- "$@" 2>&1 > /dev/null | head -n1`:
    # - Can succeed if a file argument is tracked by git but not staged
    # - Fails if a file argument is deleted or renamed
    # `git add --dry-run -- "$@" > /dev/null`:
    # - Can succeed if a file argument is tracked by git but not staged
    # - Can succeed if a file argument exists but is not tracked by git
    # - Fails if a file argument is deleted or renamed
    # `git rm -r --cached --dry-run --quiet -- "$@"`:
    # - Can succeed if a file argument is tracked by git but not staged
    # - Fails if a file argument has both staged and unstaged changes
    # `git commit --dry-run --quiet --untracked-files=no --null -- "$@" 2>&1 > /dev/null | head -n1`:
    # - Can succeed if a file argument is tracked by git but not staged
    # - Fails during a merge conflict
    local file
    for file in "$@"; do
        # --diff-filter=u ignores unmerged files
        # Return code 0 if no diff, 1 if diff, other if error
        local diff_status
        git diff --staged --diff-filter=u --quiet -- "$file"
        diff_status=$?
        if ((diff_status != 1)); then
            if ((diff_status == 0)); then
                >&2 echo "error: pathspec '$file' did not match any staged files"
            fi
            return 1
        fi
    done

    return 0
)

# Returns the number of files (0, 1, or 2) to unstage, according to a line of
# output from `git status --porcelain=v1`.
# $1: the line of output
get_count_to_unstage() {
    local line="$1"
    local status="${line:0:2}"
    if [[ "${status:0:1}" == ' '
        || "$status" == 'DD'
        || "$status" == 'AU'
        || "$status" == 'UD'
        || "$status" == 'UA'
        || "$status" == 'DU'
        || "$status" == 'AA'
        || "$status" == 'UU' ]]; then
        # Conflicted: no files to unstage
        return 0
    elif [[ "${status:0:1}" == 'R' ]]; then
        # Renamed in index: 2 files to unstage (spans 2 lines)
        return 2
    fi
    # All other cases: 1 file to unstage
    return 1
}

# Reads options into option globals, or exits with status 1 if there's a bad
# option.
read_args() {
    OPTIND=1
    local opt
    while getopts ":Av" opt; do
        case "$opt" in
        A)  opt_all=1
            ;;
        v)  opt_verbosity=1
            ;;
        ?)  show_help
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

    # If we're not in a git repository, then display an error and exit
    # Assumption: the path and contents of the git dir, the path and contents of
    # the index file, the path of the working tree, and the path of the working
    # directory are not changed by another process throughout program execution
    local git_dir
    git_dir="$(git rev-parse --git-dir)"
    if (($? != 0)); then
        exit 1
    fi

    # Determine which treeish to use for `git reset`. If HEAD is invalid (we are
    # on an unborn branch), then pass HEAD to `git reset`. Otherwise, pass the
    # SHA-1 hash of the commit.
    local reset_treeish
    reset_treeish="$(git rev-parse --revs-only HEAD)"
    if (($? != 0)); then
        exit 1
    fi
    if [[ -z "$reset_treeish" ]]; then
        reset_treeish='HEAD'
    fi

    read_args "$@"
    shift "$((OPTIND-1))" # Reset in case getopts was used previously in the script

    create_lock_file "$git_dir"

    # TODO: add -h, -p, -n, -N (undo intent to add), -e (ignore errors)
    if ((opt_all == 0)); then
        if (($# == 0)); then
            no_arguments
            remove_lock_file
            exit 1
        fi

        check_file_arguments "$@"
        if (($? != 0)); then
            remove_lock_file
            exit 1
        fi
    fi

    local line
    local files_to_unstage
    local line_is_rename=0
    local lines_done=0
    files_to_unstage=()
    # Read lines using null terminator as the delimiter
    while IFS='' read -r -d $'\0' line; do
        if ((line_is_rename == 1)); then
            files_to_unstage+=("$line")
            line_is_rename=0
        else
            if [[ "$line" == 'Done' ]]; then
                lines_done=1
            else
                local count_to_unstage
                get_count_to_unstage "$line"
                count_to_unstage=$?
                if ((count_to_unstage == 1)); then
                    files_to_unstage+=("${line:3}")
                elif ((count_to_unstage == 2)); then
                    files_to_unstage+=("${line:3}")
                    line_is_rename=1
                fi
            fi
        fi
    done < <(
        cd -- "${GIT_PREFIX:-.}"
        # --untracked-files=no makes the output smaller
        local status_status
        if ((opt_all == 1)); then
            git status --untracked-files=no -z
            status_status=$?
        else
            git status --untracked-files=no -z -- "$@"
            status_status=$?
        fi
        if ((status_status == 0)); then
            echo -en 'Done\0'
        fi
    )
    if ((lines_done == 0)); then
        >&2 echo 'git status failed, exiting'
        remove_lock_file
        exit 1
    fi

    # Remove lock file, so `git reset` can run
    remove_lock_file
    if (($? != 0)); then
        exit 1
    fi

    if ((${#files_to_unstage[@]} == 0)); then
        >&2 echo 'No changes made to index.'
    else
        # We need to redirect the output even after adding --quiet because the
        # command still prints information during a merge conflict
        git reset --quiet "$reset_treeish" -- "${files_to_unstage[@]}" > /dev/null
        if (($? != 0)); then
            exit 1
        fi
        if ((opt_verbosity == 1)); then
            local file
            for file in "${files_to_unstage[@]}"; do
                echo "unstage '$file'"
            done
        fi
    fi
}

main "$@"
