#!/bin/bash

# Exit on certain errors
set -u

show_help() {
    >&2 echo "Bad option -$OPTARG...no changes made to index"
    >&2 echo 'Usage: git unstage [-A] [-v] [--] [FILE]...'
    >&2 echo
    >&2 echo '    -A                    unstage all files in the index'
    >&2 echo '    -v                    be verbose'
    >&2 echo
}

no_changes() {
    >&2 echo 'Nothing specified, nothing unstaged.'
    >&2 echo "Maybe you wanted to say 'git unstage -A'?"
}

# Returns 1 if any file argument is not staged
check_file_arguments() {
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
    cd -- "${GIT_PREFIX:-.}"
    local file
    for file in "$@"; do
        # --diff-filter=u ignores unmerged files
        git diff --staged --diff-filter=u --quiet -- "$file"
        if (($? == 0)); then
            echo "error: pathspec '$file' did not match any staged files"
            return 1
        fi
    done
    cd -- "$OLDPWD"
    return 0
}

get_count_to_unstage() {
    local line="$1"
    if [[ -z "$line" ]]; then
        return 1
    fi
    local status="${line:0:2}"
    local file="${line:3}"
    if [[ "${status:0:1}" == ' '
        || "$status" == 'DD'
        || "$status" == 'AU'
        || "$status" == 'UD'
        || "$status" == 'UA'
        || "$status" == 'DU'
        || "$status" == 'AA'
        || "$status" == 'UU' ]]; then
        return 0
    elif [[ "${status:0:1}" == 'R' ]]; then
        return 2
    fi
    return 1
}

# Option globals
opt_all=0
opt_verbosity=0

# Read options into option globals, or exit with status 1 if there's a bad option
read_args() {
    # If we're not in a git repository, then display an error and exit
    git rev-parse --git-dir > /dev/null
    if (($? != 0)); then
        exit 1
    fi

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
    read_args "$@"
    shift "$((OPTIND-1))" # Reset in case getopts was used previously in the script

    # TODO: add -h, -p, -n, -N (undo intent to add), -e (ignore errors)
    if ((opt_all == 0)); then
        if (($# == 0)); then
            no_changes
            exit 1
        fi

        check_file_arguments "$@"
        if (($? == 1)); then
            exit 1
        fi
    fi

    local line
    local files_to_unstage
    local line_is_rename=0
    files_to_unstage=()
    # Read lines using null terminator as the delimiter
    while IFS='' read -r -d $'\0' line; do
        if ((line_is_rename == 1)); then
            files_to_unstage+=("$line")
            line_is_rename=0
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
    done < <(
        cd -- "${GIT_PREFIX:-.}"
        # --untracked-files=no makes the output smaller
        if ((opt_all == 1)); then
            git status --untracked-files=no -z
        else
            git status --untracked-files=no -z -- "$@"
        fi
    )

    if ((${#files_to_unstage[@]} == 0)); then
        >&2 echo 'No changes made to index.'
    else
        # We need to redirect the output even after adding --quiet because the
        # command still prints information during a merge conflict
        git reset --quiet HEAD -- "${files_to_unstage[@]}" > /dev/null
        if ((opt_verbosity == 1)); then
            local file
            for file in "${files_to_unstage[@]}"; do
                echo "unstage '$file'"
            done
        fi
    fi
}

main "$@"
