#!/bin/sh
# Adapts a volume of a Bitnami database chart (mounted on /volume) to the official image of the database. Executed in
# the official image, as root, by 0001-database-bitnami-to-official-image.sh.
#
# Environment: DB_TYPE, DB_UID and DB_GID (user and group running the database).
set -eu

DATA=/volume/data
if [ ! -d "$DATA" ]; then
  echo "No data directory in the volume, nothing to migrate"
  exit 0
fi

if [ "$DB_TYPE" = "postgresql" ]; then
  # Bitnami keeps the configuration files in the image and starts PostgreSQL with the path to them
  if [ ! -f "$DATA/postgresql.conf" ]; then
    echo "Creating postgresql.conf from the sample of the image"
    cp /usr/share/postgresql/postgresql.conf.sample "$DATA/postgresql.conf"
    # Bitnami listens on all interfaces
    sed -ri "s/^#?(listen_addresses)\s*=\s*\S+.*/\1 = '*'/" "$DATA/postgresql.conf"
  fi
  if [ ! -f "$DATA/pg_hba.conf" ]; then
    echo "Creating pg_hba.conf"
    # The rules of the official image, with md5 for remote connections like Bitnami: it also accepts the SCRAM passwords
    cat > "$DATA/pg_hba.conf" << 'EOF'
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
host    all             all             all                     md5
EOF
  fi
fi

echo "Changing the owner of the data to $DB_UID:$DB_GID"
chown "$DB_UID:$DB_GID" /volume
chown -R "$DB_UID:$DB_GID" "$DATA"
