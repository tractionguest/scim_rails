#!/usr/bin/env zsh
UPSTREAM=$HOME/src/guest/scim_rails_upstream
OURS=$HOME/src/guest/scim_rails

FPATH=$1
OUR_PATH=$OURS/$FPATH
UPSTREAM_PATH=$UPSTREAM/$FPATH

if [[ ! -f $OUR_PATH ]]; then
  echo "*** FATAL: Could not find file $OUR_PATH"
  exit 1
fi
if [[ ! -f $UPSTREAM_PATH ]]; then
  echo "*** FATAL: Could not find file $UPSTREAM_PATH"
  exit 1
fi

echo "  OURS: ${OUR_PATH}"
echo "THEIRS: ${UPSTREAM_PATH}"
nvim -d $OUR_PATH $UPSTREAM_PATH

