#!/bin/sh
# Upgrades the data of PostgreSQL in the volume (mounted on /volume) to the major version of the image, with pg_upgrade
# and hard links: the new cluster is created in "<new major>/docker" next to the old one, which is kept in
# "<old major>/docker" (unusable once the new one has started, to be deleted once the upgrade is validated). Executed in
# the official image of the new version, as root, by 0003-postgresql-major-upgrade.sh. Prints "POSTGRESQL_MAJOR=<major>"
# for the data of the volume once upgraded.
#
# The binaries of the old version are installed from the package repositories of the image (Debian or Alpine). The new
# cluster is initialized with the settings of the old one that pg_upgrade requires to match (superuser, encoding,
# locale, checksums) and gets its connection settings (pg_hba.conf, pg_ident.conf, postgresql.auto.conf); the other
# settings of postgresql.conf are not carried over.
#
# Environment: DB_MAJOR (major version of the image), DB_UID and DB_GID (user and group running the database).
set -eu

NEW=$DB_MAJOR
cd /volume

if [ -f "$NEW/docker/PG_VERSION" ]; then
  echo "The volume already contains the data of PostgreSQL $NEW"
  echo "POSTGRESQL_MAJOR=$NEW"
  exit 0
fi

# The latest cluster older than the version of the image
OLD=""
for version in [0-9]*/docker/PG_VERSION; do
  [ -f "$version" ] || continue
  found=$(cat "$version")
  if [ "$found" -lt "$NEW" ] && { [ -z "$OLD" ] || [ "$found" -gt "$OLD" ]; }; then
    OLD=$found
  fi
done
if [ -z "$OLD" ]; then
  echo "No data of a version older than PostgreSQL $NEW in the volume, nothing to upgrade"
  exit 0
fi
OLD_DATA=/volume/$OLD/docker
NEW_DATA=/volume/$NEW/docker
echo "Upgrading the data of PostgreSQL $OLD ($OLD_DATA) to PostgreSQL $NEW ($NEW_DATA)"

getent passwd "$DB_UID" > /dev/null || { echo "ERROR: no user with the uid $DB_UID in the image" >&2; exit 1; }
# Runs a command as the user of the database (initdb and pg_upgrade refuse to run as root)
as_db() {
  if command -v gosu > /dev/null; then
    gosu "$DB_UID:$DB_GID" "$@"
  elif command -v su-exec > /dev/null; then
    su-exec "$DB_UID:$DB_GID" "$@"
  else
    echo "ERROR: neither gosu nor su-exec in the image, cannot run commands as the user of the database" >&2
    exit 1
  fi
}

# Binaries of both versions
NEW_BIN=$(dirname "$(command -v postgres)")
if command -v apt-get > /dev/null; then
  echo "Installing the binaries of PostgreSQL $OLD with apt-get"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends "postgresql-$OLD" > /dev/null
  OLD_BIN=/usr/lib/postgresql/$OLD/bin
elif command -v apk > /dev/null; then
  echo "Installing the binaries of PostgreSQL $OLD with apk"
  apk add --no-cache --quiet "postgresql$OLD"
  OLD_BIN=/usr/libexec/postgresql$OLD
else
  echo "ERROR: neither apt-get nor apk in the image, cannot install the binaries of PostgreSQL $OLD" >&2
  exit 1
fi
[ -x "$OLD_BIN/postgres" ] || { echo "ERROR: $OLD_BIN/postgres not found after the installation" >&2; exit 1; }

# Settings of the old cluster that the new one must share, read in single-user mode (which also completes the recovery
# of a cluster that was not shut down cleanly, as pg_upgrade requires)
chown -R "$DB_UID:$DB_GID" "$OLD_DATA"
chmod 700 "$OLD_DATA"
if [ "$OLD" -ge 17 ]; then
  locale_columns="d.datlocprovider AS provider, d.datlocale AS locale"
elif [ "$OLD" -ge 15 ]; then
  locale_columns="d.datlocprovider AS provider, d.daticulocale AS locale"
else
  locale_columns="'c' AS provider"
fi
# The query on a single line (each line is a statement in single-user mode)
settings=$(echo "SELECT r.rolname AS superuser, pg_encoding_to_char(d.encoding) AS encoding, d.datcollate AS collate," \
  "d.datctype AS ctype, $locale_columns FROM pg_database d, pg_roles r WHERE d.datname = 'template0' AND r.oid = 10;" \
  | as_db "$OLD_BIN/postgres" --single -D "$OLD_DATA" template1 2> /tmp/settings.log) \
  || { cat /tmp/settings.log >&2; exit 1; }
# A column per line: "<n>: <name> = "<value>"	(typeid = ...", null columns are not printed
setting() {
  echo "$settings" | sed -n "s/^.*: $1 = \"\(.*\)\"[[:space:]]*(typeid.*$/\1/p" | head -n 1
}
SUPERUSER=$(setting superuser)
[ -n "$SUPERUSER" ] || { echo "ERROR: cannot read the settings of the old cluster:" >&2; echo "$settings" >&2; exit 1; }
INITDB_ARGS="--username=$SUPERUSER --encoding=$(setting encoding) --lc-collate=$(setting collate) --lc-ctype=$(setting ctype)"
if [ "$NEW" -ge 15 ]; then
  case "$(setting provider)" in
    i) INITDB_ARGS="$INITDB_ARGS --locale-provider=icu --icu-locale=$(setting locale)" ;;
    b) INITDB_ARGS="$INITDB_ARGS --locale-provider=builtin --builtin-locale=$(setting locale)" ;;
    *) INITDB_ARGS="$INITDB_ARGS --locale-provider=libc" ;;
  esac
fi
checksums=$(as_db "$OLD_BIN/pg_controldata" -D "$OLD_DATA" | sed -n 's/^Data page checksum version: *//p')
if [ "${checksums:-0}" != 0 ]; then
  INITDB_ARGS="$INITDB_ARGS --data-checksums"
elif [ "$NEW" -ge 18 ]; then
  # Enabled by default since PostgreSQL 18
  INITDB_ARGS="$INITDB_ARGS --no-data-checksums"
fi

# The new cluster, removed when the upgrade fails so that it is retried from scratch
DONE=""
cleanup() {
  if [ -z "$DONE" ] && [ -d "$NEW_DATA" ]; then
    echo "Removing the incomplete $NEW_DATA"
    rm -rf "$NEW_DATA"
  fi
}
trap cleanup EXIT
echo "Initializing the cluster of PostgreSQL $NEW: initdb $INITDB_ARGS"
mkdir -p "$NEW_DATA"
chown "$DB_UID:$DB_GID" "/volume/$NEW" "$NEW_DATA"
chmod 700 "$NEW_DATA"
# shellcheck disable=SC2086
as_db "$NEW_BIN/initdb" --pgdata="$NEW_DATA" --auth-local=trust --auth-host=scram-sha-256 $INITDB_ARGS > /tmp/initdb.log \
  || { cat /tmp/initdb.log >&2; exit 1; }
# Connection settings of the old cluster, and listening on all interfaces like the entrypoint of the image
for file in pg_hba.conf pg_ident.conf postgresql.auto.conf; do
  [ -f "$OLD_DATA/$file" ] && cp -p "$OLD_DATA/$file" "$NEW_DATA/$file"
done
sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" "$NEW_DATA/postgresql.conf"

# pg_upgrade writes its logs, and the sockets of the servers it starts, in the current directory
WORK=/tmp/pg_upgrade
mkdir -p "$WORK"
chown "$DB_UID:$DB_GID" "$WORK"
cd "$WORK"
upgrade() {
  as_db "$NEW_BIN/pg_upgrade" --old-bindir="$OLD_BIN" --new-bindir="$NEW_BIN" --old-datadir="$OLD_DATA" \
    --new-datadir="$NEW_DATA" --username="$SUPERUSER" --link "$@"
}
echo "Checking the clusters with pg_upgrade"
upgrade --check
echo "Upgrading with pg_upgrade (hard links)"
upgrade
DONE=1
echo "The data of PostgreSQL $OLD was upgraded to PostgreSQL $NEW. Once validated, $OLD_DATA can be deleted."

# The statistics of the optimizer: none are upgraded before PostgreSQL 18, some are not since
echo "Computing the statistics of the optimizer"
if [ "$NEW" -ge 18 ]; then
  missing_only="--missing-stats-only"
else
  missing_only=""
fi
as_db "$NEW_BIN/pg_ctl" --pgdata="$NEW_DATA" --wait --silent --log=/tmp/analyze.log \
  --options="-c listen_addresses='' -c unix_socket_directories='$WORK'" start
# shellcheck disable=SC2086
as_db "$NEW_BIN/vacuumdb" --host="$WORK" --username="$SUPERUSER" --all --analyze-in-stages $missing_only > /dev/null \
  || echo "WARNING: the statistics could not be computed, run vacuumdb --all --analyze-in-stages on the database" >&2
as_db "$NEW_BIN/pg_ctl" --pgdata="$NEW_DATA" --wait --silent --mode=fast stop
echo "POSTGRESQL_MAJOR=$NEW"
