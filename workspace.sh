#!/usr/bin/env bash
# vim: set expandtab sw=4 ts=4:

## This little script accompanies a go mod uber repo, that is, a Git repo that aggregates modules pertaining
## to a single project linearly through git submodules.

set -euo pipefail
IFS=$'\n'

## Load all subdirectories siblings of this script.
mods=()
while IFS='' read -r line; do mods+=("$line"); done < \
    <(find "$(dirname "${0}")" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -exec basename {} ';' | sort)

## Return the repo name of origin remote
##   It expect the origin to be `git@github.com:<orgname>/<repo-name>.git` (ssh format).
get_repo() {
	local mod="${1}"
	git -C "$mod" remote get-url origin | cut -d':' -f2 | cut -d'.' -f1
}

## Edits a module gomod. Args:
##  $1: module to edit
##  $2: array of flags to go mod edit
edit_mod() {
    local mod="${1}"
    shift
    local flags=("$@")
    go mod edit "${flags[@]}" "$mod/go.mod"
    echo $mod
}

do_local() {
    local flags=()
    for mod in "${mods[@]}"; do
        flags+=("-replace=github.com/$(get_repo $mod)=../$mod")
    done
    for i in "${!mods[@]}"; do
        local rep=("${flags[@]}")
        unset 'rep['"$i"']'
        rep=("${rep[@]}")

        edit_mod "${mods[$i]}" "${rep[@]}"
    done
}

do_remote() {
    local flags=()
    for mod in "${mods[@]}"; do
        flags+=("-dropreplace=github.com/$(get_repo $mod)")
    done
    for i in "${!mods[@]}"; do
        local rep=("${flags[@]}")
        unset 'rep['"$i"']'
        rep=("${rep[@]}")

        edit_mod "${mods[$i]}" "${rep[@]}"
    done
}

do_refresh() {
    cd "$(dirname "${0}")"
    echo "::: Stashing all changes :::"
    git submodule foreach git stash

    echo "::: Checking out master on all submodules :::"
    git submodule foreach git checkout master

    echo "::: Rebasing all submodules origin/master :::"
    exec 3>&1
    if ! git submodule update --jobs 10 --remote --rebase 1>&3 2>&3; then
        echo "WARN: upgrade git for faster submodule updates from origin"
        git submodule update --remote --rebase
    fi

    echo "Done"
}

git-branch-name () {
    git status 2> /dev/null | \
        head -1 | \
        sed 's/^# //' | \
        sed 's/^On branch //' |\
        sed 's/HEAD detached at //'
}

do_branches() {
    for D in *;
    do
        if [ -d "${D}" ]; then
            cd "${D}"
            printf "${D}\t"
            git-branch-name
            cd ..
        fi
    done
}

do_branches_col() {
    if which column &>/dev/null; then
        do_branches | column -t
    else
        do_branches
    fi
}

print_usage() {
    echo "Usage: $0 {local|remote|master}" >&2
    echo
    echo "  local       adds \`replace\` directives to all go.mod files to make dependencies point to the local workspace"
    echo "  remote      removes the \`replace\` directives introduced by \`local\`"
    echo "  refresh     refreshes all submodules from origin/master, stashing all local changes first, then checking out master"
    echo "  branches    lists all the repos and the branch checked out"
    echo ""
}

if [[ -z ${1:-} ]]; then
    print_usage
    exit 1
fi

case "$1" in
    local) do_local ;;
    remote) do_remote ;;
    refresh) do_refresh ;;
    branches) do_branches_col ;;
    *) print_usage; exit 1; ;;
esac
