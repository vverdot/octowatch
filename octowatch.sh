#!/bin/bash

## Some vars

VERSION="0.3"
GITHUB_API="https://api.github.com/repos"
OW_CONFIG_DIR="$HOME/.octowatch.d"

# Default delay: 1 day (86400 seconds)
OW_CACHE_DELAY=86400
OW_CACHE_FILE="$OW_CONFIG_DIR/cache.json"
OW_WATCH_FILE="$OW_CONFIG_DIR/watch.lst"
OW_CONF_FILE="$OW_CONFIG_DIR/config"

if [ ! -d "$OW_CONFIG_DIR" ] ; then
    mkdir "$OW_CONFIG_DIR"
elif [ -f "$OW_CONF_FILE" ] ; then
    source "$OW_CONF_FILE"
fi

## Utility functions

setColors() {
    ncolors=$(tput colors)

    if [ $ncolors -ge 8 ]; then
        bold="$(tput bold)"
        underline="$(tput smul)"
        standout="$(tput smso)"
        normal="$(tput sgr0)"
        black="$(tput setaf 0)"
        red="$(tput setaf 1)"
        green="$(tput setaf 2)"
        yellow="$(tput setaf 3)"
        blue="$(tput setaf 4)"
        magenta="$(tput setaf 5)"
        cyan="$(tput setaf 6)"
        white="$(tput setaf 7)"
    fi
}

disableColors() {
    bold=""
    underline=""
    standout=""
    normal=""
    black=""
    red=""
    green=""
    yellow=""
    blue=""
    magenta=""
    cyan=""
    white=""
}

usage() {
    echo "octowatch $VERSION"
    cat <<EOF
    Usage: octowatch [options] [REPOSITORY] ...

    REPOSITORY: directory or current if omitted.

    Options:
    --help	: display command usage
    --add		: add repository to watch list
    --list	: show status of watched repositories
EOF
}

usage_error() {
    echo "octowatch: ${1:-'Unexpected Error'}"
    echo "Try 'octowatch --help' for more information."
    exit 1
}

msg() {
    echo "$1"
}

## Functions

checkWithCache() {
    cd "$2"
    current=$(git rev-parse HEAD)
    cached=$(jq -r '.commit' <<< "$1")
    if [ "$current" == "$cached" ] ; then
        return 0
    else
        return 1
    fi
}

refreshCache() {
    GIT_API="$GITHUB_API/$1"

    #msg "Refresh - using GITHUB API URL: $GIT_API"

    COMMIT=$(curl -sSL ${GIT_API}/commits?per_page=1 | jq -r '.[0].sha')

    # Check GIT API call result
    if [ "$?" -ne 0 ] ; then
        msg "Error accessing Github API. [$GIT_API]."
        exit 1
    fi

    if [ "$COMMIT" == "null" ] ; then
        msg "No commit found! Aborting."
        exit 1
    fi


    tmpfile=$(mktemp /tmp/octowatch.XXX)

    jq "(.[] | select(.repository==\"$1\") | .verified) |= \"$(date +%s)\" | \
        (.[] | select(.repository==\"$1\") | .commit) |= \"$COMMIT\"" "$OW_CACHE_FILE" > "$tmpfile"

    if [ $? -eq 0 ] ; then
        cp -f "$tmpfile" "$OW_CACHE_FILE"
        rm "$tmpfile"
        return 0
    fi

    return 1
}

updateCache() {
    GIT_API="$GITHUB_API/$1"

    #msg "Update - using GITHUB API URL: $GIT_API"

    COMMIT=$(curl -sSL ${GIT_API}/commits?per_page=1 | jq -r '.[0].sha')

    # Check GIT API call result
    if [ "$?" -ne 0 ] ; then
        msg "Error accessing Github API. [$GIT_API]."
        exit 1
    fi

    if [ "$COMMIT" == "null" ] ; then
        msg "No commit found! Aborting."
        exit 1
    fi


    tmpfile=$(mktemp /tmp/octowatch.XXX)

    jsonStr="{\"repository\": \"${1}\",\"verified\": \"$(date +%s)\", \"commit\": \"${COMMIT}\"}"
    jq ". |= (.+ [$jsonStr])" "$OW_CACHE_FILE" > "$tmpfile"

    if [ $? -eq 0 ] ; then
        cp -f "$tmpfile" "$OW_CACHE_FILE"
        rm "$tmpfile"
        return 0
    fi

    return 1
}

getCache() {
    CACHED_DATA=$(jq "[.[] | select(.repository==\"$1\")] | .[0]" "$OW_CACHE_FILE")

    # Check parsing problems
    if [ "$CACHED_DATA" == "" ] ; then
        msg "Fatal parsing error. Check or delete cachefile "$OW_CACHE_FILE")"
        exit 1
    fi
}

# $1: Repository PATH
# $2: filter: "updates"
printRepoStatus() {

    F_UPDATES=
    if [ "$2" == "updates" ] ; then
        F_UPDATES=1
    fi

    if [ ! -d "$1" ] ; then
        msg "Invalid directory [$1]. Cannot print status."
        return 0
    else
        repoDir="$1"
    fi

    cd "$repoDir"

    # Get git remote.origin.url
    GIT_REMOTE=$(git config --get remote.origin.url)
    if [ "$?" -ne 0 ] ; then
        msg "Invalid GIT Repository [$1]"
        return 1
    fi

    # Test if git remote is from github
    if [[ ! "$GIT_REMOTE" == *"github.com"* ]] ; then
        msg "Couldn't find a valid Github Repository: $GIT_REMOTE"
        return 1
    fi

    # Get full repo name
    GIT_REPO="${GIT_REMOTE#*github.com/}"
    GIT_REPO="${GIT_REPO%'.git'}"

    CACHED_DATA="null"

    if [ -f "$OW_CACHE_FILE" ] ; then
        getCache "$GIT_REPO"
    else
        echo '[]' > "$OW_CACHE_FILE"
    fi

    if [ "$CACHED_DATA" == "null" ] ; then
        updateCache "$GIT_REPO"
        getCache "$GIT_REPO"
    fi

    last_verification=$(jq -r '.verified' <<< "$CACHED_DATA")
    is_expired=$(( ($(date +%s) - $last_verification) > $OW_CACHE_DELAY ))

    if [ $is_expired -eq 1 ] ; then
        refreshCache "$GIT_REPO"
        getCache "$GIT_REPO"
    fi

    checkWithCache "$CACHED_DATA" "$repoDir"

    if [ $? -eq 0 ] ; then
        returnStr="[$bold${green}uptodate$normal]"
        if [[ $F_UPDATES ]] ; then
            return 0
        fi
    else
        returnStr="[$bold${red}outdated$normal]"
    fi

    echo " $returnStr $repoDir ($GIT_REPO)"

    return 0
}

showStatus() {

    if [ ! -f "$OW_WATCH_FILE" ] ; then
        msg "No watched repository."
        return 0
    fi

    while read -r line || [[ -n "$line" ]]; do
        printRepoStatus $line $@
    done < "$OW_WATCH_FILE"
    return 0
}

showUpdates() {
    showStatus "updates"
}

#TODO: FIX files command

## BEGIN SCRIPT

setColors

REPO_DIR='.'

# Flags
F_ADD=
CMD=

OPTS=$(getopt --shell bash --name octowatch --long add,help,list,updates,no-colors --options nlua -- "$@")
eval set -- "$OPTS"

# Extract options and arguments
while true ; do
    case "$1" in
        --) shift ; break ;;
        -n|--no-colors) disableColors ; shift ;;
        --help) usage ; exit 0 ;;
        --list|-l) CMD="showStatus" ; shift ;;
        --updates|-u) CMD="showUpdates" ; shift ;;
        -a|--add) F_ADD=1 ; shift ;;
        *) echo "usage error" ; exit 1  ;;
    esac
done

# Run provided command
case "$CMD" in
    "showStatus") showStatus ; exit 0 ;;
    "showUpdates") showUpdates ; exit 0 ;;
esac

# TODO: set appropriate directory first (and this for all params)
if [ "$#" -gt 0 ] ; then
    if [ -d "$1" ] ; then
        REPO_DIR="$1"
    else
        msg "Invalid argument. $1 is not a valid directory."
    fi
fi

REPO_DIR="$(realpath $REPO_DIR)"

printRepoStatus "$REPO_DIR"

if [ $? -ne 0 ] ; then
    exit $?
fi

# --add switch
if [[ "$F_ADD" ]] ; then
    tmpfile=$(mktemp /tmp/octo.XXX)
    if [ -f "$OW_WATCH_FILE" ] ; then
        cp "$OW_WATCH_FILE" "$tmpfile"
    fi
    echo "$REPO_DIR" >> "$tmpfile"
    sort "$tmpfile" | uniq > "$OW_WATCH_FILE"
    rm "$tmpfile"
    msg "$bold  => Added to watch list. $normal"
fi

exit 0
