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
    # See tempfile.c:remove_tempfiles()
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
}

# Near-atomically deletes lock and unsets lock_file.
remove_lock_file() {
    local local_lock_file
    local_lock_file="$lock_file"

    # We can't delete the lock file and unset lock_file atomically (there could
    # be a signal), but the only damage is that the lock file lingers.
    lock_file=''

    # See tempfile.c:remove_tempfiles()
    rm -- "$local_lock_file"
}

# Prints a "help" message.
# $1: the bad option
show_help() {
    >&2 echo "Bad option -$1...no changes made to index"
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
                >&2 echo "Error: pathspec '$file' did not match any staged files"
            fi
            return 1
        fi
    done

    return 0
)

# Reads options into option globals, or exits with status 1 if there's a bad
# option. Changes the shell variables OPTARG and OPTIND.
read_args() {
    if ((OPTIND != 1)); then
        >&2 echo "BUG: OPTIND is $OPTIND"' != 1'
        exit 1
    fi

    local opt
    while getopts ":Av" opt; do
        case "$opt" in
        A)  opt_all=1
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

    # Remove CDPATH variable, if defined, to avoid breaking cd later
    unset CDPATH

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

    create_lock_file "$git_dir"

    # Determine which treeish to use for `git reset`. If HEAD is invalid (we are
    # on an unborn branch), then pass the id of the empty tree to `git reset`.
    # Otherwise, pass the SHA-1 hash of the commit.
    local empty_tree_hash="$(git hash-object -t tree /dev/null)"
    local zero_hash="0000000000000000000000000000000000000000"
    local empty_object_hash="$(git hash-object /dev/null)"
    local reset_treeish
    reset_treeish="$(git rev-parse --revs-only HEAD)"
    if (($? != 0)); then
        >&2 echo 'BUG: git rev-parse HEAD failed'
        remove_lock_file
        exit 1
    fi
    if [[ -z "$reset_treeish" ]]; then
        reset_treeish="$empty_tree_hash"
    fi

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

    # Perform a no-op to see if --ita-invisible-in-index is available.
    # Otherwise, use a best-effort approach to simulate it.
    local ita_flag_exists=0
    git diff-tree --ita-invisible-in-index "$empty_tree_hash" "$empty_tree_hash" --
    if (($? == 0)); then
        ita_flag_exists=1
    fi

    local line
    local files_maybe_ita
    local files_to_unstage
    local diff_state=0
    local lines_done=0
    files_maybe_ita=()
    files_to_unstage=()
    # Read lines using null terminator as the delimiter
    while IFS='' read -r -d $'\0' line; do
        if ((diff_state == 0)); then
            # Determine diff_state
            if [[ "$line" == 'Done' ]]; then
                lines_done=1
            else
                if [[ "$ita_flag_exists" == 0
                    && "${line:15:40}" == "$zero_hash"
                    && "${line:56:40}" == "$empty_object_hash" ]]; then
                    # File is ITA or empty staged
                    diff_state=1
                elif [[ "${line:97}" != 'U' ]]; then
                    # File is staged
                    diff_state=2
                else
                    # File is unmerged
                    diff_state=3
                fi
            fi
        elif ((diff_state == 1)); then
            files_maybe_ita+=("$line")
            diff_state=0
        elif ((diff_state == 2)); then
            files_to_unstage+=("$line")
            diff_state=0
        else
            diff_state=0
        fi

    done < <(
        cd -- "${GIT_PREFIX:-.}"

        local diff_flags=("--cached" "--no-renames" "-z")
        if ((ita_flag_exists == 1)); then
            diff_flags+=("--ita-invisible-in-index")
        fi

        # In the descriptions below, two-letter pairs (e.g. DA, DD) refer to the <XY> state of the
        # file, as printed near the start of each line of output from `git status --porcelain=v2`
        # (2.11+).
        # Current approach:
        # - `--ita-invisible-in-index` is only available in 2.11+, but no other way to guarantee
        #   that ITA files are handled correctly (impossible edge case: DA/DD, empty in index)
        # - Inaccurate output for DA/DD/DR files (not an issue for us)
        # `git diff --staged --raw --abbrev=40 --no-renames --ita-invisible-in-index -z -- "$@"`:
        # - `--ita-invisible-in-index` is only available in 2.11+ (see above)
        # - Inaccurate output for DA/DD/DR files (not an issue for us, fixed in 2.19+)
        # `git --no-optional-locks status --untracked-files=no --porcelain -z -- "$@"`:
        # - `--untracked-files=no` improves performance, but only slightly: reads each file in
        #   working tree, outputs a line for each dirty file in working tree
        # - `--no-renames` is only available in 2.18+
        # - Porcelain version 1 has ambiguous DD (unmerged both deleted, or deleted in index +
        #   deleted in working tree)
        # - Need `--no-optional-locks` (2.15+) to avoid locking index
        # - Need to lock refs to avoid race condition of changing HEAD
        # `git --no-optional-locks -c status.relativePaths=false status --untracked-files=no --porcelain=v2 -z -- "$@"`:
        # - `--untracked-files=no` improves performance, but only slightly (see above)
        # - `--no-renames` is only available in 2.18+
        # - Porcelain version 2 is only available in 2.11+
        # - Need `--no-optional-locks` (2.15+) to avoid locking index
        # - Need to lock refs to avoid race condition of changing HEAD
        local diff_status
        if ((opt_all == 1)); then
            git diff-index "${diff_flags[@]}" "$reset_treeish" --
            diff_status=$?
        else
            git diff-index "${diff_flags[@]}" "$reset_treeish" -- "$@"
            diff_status=$?
        fi
        if ((diff_status == 0)); then
            echo -en 'Done\0'
        fi
    )

    if ((lines_done == 0)); then
        >&2 echo 'BUG: git diff-index --cached failed'
        remove_lock_file
        exit 1
    fi

    if ((${#files_maybe_ita[@]} > 0)); then
        diff_state=0
        lines_done=0
        while IFS='' read -r -d $'\0' line; do
            if ((diff_state == 0)); then
                # Determine diff_state
                if [[ "$line" == 'Done' ]]; then
                    lines_done=1
                else
                    if [[ "${line:15:40}" == "$zero_hash" && "${line:56:40}" == "$empty_object_hash" ]]; then
                        # File is empty staged
                        diff_state=1
                    else
                        # File is ITA
                        diff_state=2
                    fi
                fi
            elif ((diff_state == 1)); then
                files_to_unstage+=("$line")
                diff_state=0
            else
                diff_state=0
            fi
        done < <(
            git diff-index --no-renames -z "$reset_treeish" -- "${files_maybe_ita[@]}"
            if (($? == 0)); then
                echo -en 'Done\0'
            fi
        )
        if ((lines_done == 0)); then
            >&2 echo 'BUG: git diff-index failed'
            remove_lock_file
            exit 1
        fi
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
            >&2 echo 'BUG: git reset failed'
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
