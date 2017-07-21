#!/bin/bash

## Some vars

GITHUB_API="https://api.github.com/repos"
OW_CONFIG_DIR="$HOME/.octowatch.d"

OW_CACHE_DELAY=3600
OW_CACHE_FILE="$OW_CONFIG_DIR/cache.json"

if [ ! -d "$OW_CONFIG_DIR" ] ; then
	mkdir "$OW_CONFIG_DIR"
elif [ -f "$OW_CONFIG_DIR/config" ] ; then
	source "$OW_CONFIG_DIR/config"
fi

## Utility functions

msg() {
	echo "$1"
}

## Functions

checkWithCache() {
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
	
	msg "Refresh - using GITHUB API URL: $GIT_API"

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
	
	msg "Update - using GITHUB API URL: $GIT_API"

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

## BEGIN SCRIPT

# Get git remote.origin.url
GIT_REMOTE=$(git config --get remote.origin.url)
if [ "$?" -ne 0 ] ; then
	msg "Nothing to watch here!"
	#msg "No GIT Remote Origin URL."
	exit 1
fi

# Test if git remote is from github
if [[ ! "$GIT_REMOTE" == *"github.com"* ]] ; then 
	msg "Couldn't find a valid Github Repository: $GIT_REMOTE"
	exit 1
fi

# Build git API URL
#GIT_API="https://api.github.com/repos${GIT_REMOTE#*github.com}"
#GIT_API=${GIT_API%'.git'}

# Get full repo name
GIT_REPO="${GIT_REMOTE#*github.com/}"
GIT_REPO="${GIT_REPO%'.git'}"


##curl -sSL ${GIT_API}/releases?per_page=1
#RELEASE=$(curl -sSL ${GIT_API}/releases?per_page=1 | jq -r '.[0].name')
#
## Check GIT API call result
#if [ "$?" -ne 0 ] ; then
#	msg "Error accessing Github API. [$GIT_API]."
#	exit 1
#fi
#
#if [ "$RELEASE" == "null" ] ; then
#	msg "No release found! Fallback to tags.."
#else
#	msg "Release: $RELEASE"
#	exit 0
#fi
#
## TAGS Fallback
#TAG=$(curl -sSL ${GIT_API}/tags?per_page=1 | jq -r '.[0].name')
#
## Check GIT API call result
#if [ "$?" -ne 0 ] ; then
#	msg "Error accessing Github API. [$GIT_API]."
#	exit 1
#fi
#
#if [ "$TAG" == "null" ] ; then
#	msg "No tag found! Fallback to commits.."
#else
#	msg "Tag: $TAG"
#	exit 0
#fi

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

checkWithCache "$CACHED_DATA"

if [ $? -eq 0 ] ; then
	msg "$GIT_REPO is up to date"
else
	msg "$GIT_REPO has new stuff"
fi

exit 0

