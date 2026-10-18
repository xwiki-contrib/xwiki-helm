#!/bin/sh
# Up to version 1.7 the data of PostgreSQL was in the "data" directory of the volume (layout of the Bitnami chart, kept by
# the first versions deploying the official image). Since then the chart uses the layout of the official image since
# PostgreSQL 18, for all the versions: a "<major>/docker" directory per major version, so that the clusters of two
# majors coexist in the volume during an upgrade of the major version (see 0003-postgresql-major-upgrade.sh).
# The data is moved (a rename, whatever its size) by a pod running postgresql-data-layout.sh in the official image,
# after the StatefulSet and its pod are deleted ("helm upgrade" creates them again, mounting the volume on
# /var/lib/postgresql instead of /var/lib/postgresql/data). The major version of the data is then recorded in an
# annotation of the volume claim, for the next migration.
# The claim is annotated while it is migrated, so that an interrupted migration is completed by the next run.

PENDING_ANNOTATION="xwiki.org/migration-postgresql-data-layout"
MAJOR_ANNOTATION="xwiki.org/postgresql-major"

migration_description() {
  echo "Moving the data of PostgreSQL to the directory of its major version in the volume"
}

claim() {
  echo "data-$DB_FULLNAME-0"
}

# Where the current StatefulSet mounts the volume of the data, nothing without StatefulSet
data_mount_path() {
  k get statefulset "$DB_FULLNAME" --ignore-not-found \
    -o go-template='{{ with index .spec.template.spec.containers 0 }}{{ range .volumeMounts }}{{ if eq .name "data" }}{{ .mountPath }}{{ end }}{{ end }}{{ end }}'
}

migration_needed() {
  [ "$DB_TYPE" = postgresql ] || return 1
  k get pvc "$(claim)" > /dev/null 2>&1 || return 1
  [ -z "$(annotation pvc "$(claim)" "$PENDING_ANNOTATION")" ] || return 0
  # Done when the StatefulSet already mounts the volume with the current layout. Without StatefulSet (e.g. deleted by
  # the previous migration) the layout of the volume is unknown: the pod checks it.
  [ "$(data_mount_path)" != /var/lib/postgresql ]
}

migration_apply() {
  claim=$(claim)
  annotate pvc "$claim" "$PENDING_ANNOTATION" pending
  selector=$(statefulset_selector "$DB_FULLNAME")
  if [ -n "$selector" ]; then
    delete_statefulset "$DB_FULLNAME" "$selector"
  fi
  run_pod database-pod.yaml "$DB_FULLNAME-migration" "$claim" postgresql-data-layout.sh
  major=$(sed -n 's/^POSTGRESQL_MAJOR=//p' "$RUN_POD_LOG")
  if [ -n "$major" ]; then
    annotate pvc "$claim" "$MAJOR_ANNOTATION" "$major"
  fi
  annotate pvc "$claim" "$PENDING_ANNOTATION"
}
