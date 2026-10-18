#!/bin/sh
# Moves the data of PostgreSQL from the "data" directory of the volume (mounted on /volume) to the directory of its
# major version, "<major>/docker" (layout of the official image since PostgreSQL 18). Executed in the official image,
# as root, by 0002-postgresql-data-layout.sh. Prints "POSTGRESQL_MAJOR=<major>" for the data found in the volume.
#
# Environment: DB_UID and DB_GID (user and group running the database).
set -eu

cd /volume
if [ -f data/PG_VERSION ]; then
  major=$(cat data/PG_VERSION)
  target="$major/docker"
  if [ -e "$target" ]; then
    echo "ERROR: the volume contains both the data directory and $target, remove the one that is not the data" >&2
    exit 1
  fi
  echo "Moving the data of PostgreSQL $major from data to $target"
  mkdir -p "$major"
  mv data "$target"
  chown "$DB_UID:$DB_GID" . "$major"
  echo "POSTGRESQL_MAJOR=$major"
  exit 0
fi
if [ -d data ] && [ -n "$(ls -A data)" ]; then
  echo "WARNING: the data directory of the volume does not contain a PostgreSQL cluster, it is ignored" >&2
fi

major=""
for version in [0-9]*/docker/PG_VERSION; do
  [ -f "$version" ] || continue
  found=$(cat "$version")
  if [ -z "$major" ] || [ "$found" -gt "$major" ]; then
    major=$found
  fi
done
if [ -n "$major" ]; then
  echo "The data of PostgreSQL $major is already in $major/docker"
  echo "POSTGRESQL_MAJOR=$major"
else
  echo "No data of PostgreSQL in the volume, nothing to move"
fi
