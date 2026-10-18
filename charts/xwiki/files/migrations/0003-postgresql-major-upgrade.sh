#!/bin/sh
# Upgrades the data of PostgreSQL when the major version of the image deployed by the chart (postgresql.image.tag) is
# higher than the one of the data in the volume: PostgreSQL does not do it by itself and refuses to start otherwise.
# A pod running postgresql-major-upgrade.sh in the new image installs the binaries of the previous major version (it
# needs access to the package repositories of the image) and runs pg_upgrade with hard links: the new cluster is
# created in "<new major>/docker" next to the old one, which is left in "<old major>/docker" and can be deleted once the
# upgrade is validated. The StatefulSet and its pod are deleted before ("helm upgrade" creates them again).
# The major version of the data is known from the annotation of the volume claim set by the migrations, else from the
# current StatefulSet. The claim is annotated while it is migrated, so that an interrupted upgrade is completed by the
# next run.

PENDING_ANNOTATION="xwiki.org/migration-postgresql-major-upgrade"
MAJOR_ANNOTATION="xwiki.org/postgresql-major"

migration_description() {
  echo "Upgrading the data of PostgreSQL $(data_major) to PostgreSQL $DB_MAJOR with pg_upgrade"
}

claim() {
  echo "data-$DB_FULLNAME-0"
}

# Major version of the data in the volume, nothing when unknown
data_major() {
  major=$(annotation pvc "$(claim)" "$MAJOR_ANNOTATION")
  if [ -z "$major" ]; then
    major=$(statefulset_env "$DB_FULLNAME" PGDATA | sed -n 's|^/var/lib/postgresql/\([0-9]*\)/docker$|\1|p')
  fi
  echo "$major"
}

migration_needed() {
  [ "$DB_TYPE" = postgresql ] && [ -n "$DB_MAJOR" ] || return 1
  k get pvc "$(claim)" > /dev/null 2>&1 || return 1
  [ -z "$(annotation pvc "$(claim)" "$PENDING_ANNOTATION")" ] || return 0
  major=$(data_major)
  [ -n "$major" ] && [ "$major" != "$DB_MAJOR" ]
}

migration_apply() {
  claim=$(claim)
  major=$(data_major)
  if [ -n "$major" ] && [ "$major" -gt "$DB_MAJOR" ]; then
    fail "The data is of PostgreSQL $major, it cannot be downgraded to PostgreSQL $DB_MAJOR (postgresql.image.tag)"
  fi
  annotate pvc "$claim" "$PENDING_ANNOTATION" pending
  selector=$(statefulset_selector "$DB_FULLNAME")
  if [ -n "$selector" ]; then
    delete_statefulset "$DB_FULLNAME" "$selector"
  fi
  run_pod database-pod.yaml "$DB_FULLNAME-migration" "$claim" postgresql-major-upgrade.sh
  major=$(sed -n 's/^POSTGRESQL_MAJOR=//p' "$RUN_POD_LOG")
  if [ -n "$major" ]; then
    annotate pvc "$claim" "$MAJOR_ANNOTATION" "$major"
  fi
  annotate pvc "$claim" "$PENDING_ANNOTATION"
}
