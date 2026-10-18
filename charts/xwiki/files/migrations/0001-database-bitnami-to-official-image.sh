#!/bin/sh
# Up to version 1.7 the database was deployed by the Bitnami charts, since then by the chart itself with the official
# image. The StatefulSet of the Bitnami chart has the same name as the new one but cannot be updated into it (its
# selector is immutable): it is deleted, keeping its volume claim which is then reused by the new StatefulSet (same name
# of claim template). The data is in the "data" directory of the volume in both cases, but it has to belong to the user
# of the official image and Bitnami keeps the configuration files of PostgreSQL out of it: this is fixed by a pod
# running database-bitnami-volume.sh in the official image.
# The claim is annotated while it is migrated, so that an interrupted migration is completed by the next run.

PENDING_ANNOTATION="xwiki.org/migration-database-bitnami"

migration_description() {
  echo "Replacing the StatefulSet of the Bitnami $DB_TYPE chart by the one of the official image, keeping its data"
}

# StatefulSets of the release deployed by the Bitnami chart of the database (the primary and the secondary one if any)
bitnami_statefulsets() {
  [ -n "$DB_TYPE" ] || return 0
  k get statefulsets --selector "app.kubernetes.io/instance=$RELEASE_NAME,app.kubernetes.io/name=$DB_TYPE" \
    -o go-template='{{ range .items }}{{ .metadata.name }} {{ index .metadata.labels "helm.sh/chart" }}{{ "\n" }}{{ end }}' \
    | awk -v chart="$DB_TYPE-" 'index($2, chart) == 1 { print $1 }'
}

claim() {
  echo "data-$DB_FULLNAME-0"
}

migration_needed() {
  [ -n "$DB_TYPE" ] || return 1
  [ -n "$(bitnami_statefulsets)" ] || [ -n "$(annotation pvc "$(claim)" "$PENDING_ANNOTATION")" ]
}

migration_apply() {
  statefulsets=$(bitnami_statefulsets)
  claim=$(claim)
  if [ -n "$statefulsets" ]; then
    if ! echo "$statefulsets" | grep -qx "$DB_FULLNAME"; then
      # e.g. with a name of release containing the type of database or a fullnameOverride of the Bitnami chart
      fail "The Bitnami StatefulSet(s) $(echo "$statefulsets" | tr '\n' ' ')cannot be migrated automatically: none is" \
        "named $DB_FULLNAME, the name of the StatefulSet deployed by the chart."
    fi
    if k get pvc "$claim" > /dev/null 2>&1; then
      annotate pvc "$claim" "$PENDING_ANNOTATION" pending
    else
      log "No volume claim $claim (persistence disabled?), the data of the database is not kept"
    fi
    for statefulset in $statefulsets; do
      selector=$(statefulset_selector "$statefulset")
      if [ "$statefulset" != "$DB_FULLNAME" ]; then
        log "The replicas of $statefulset are not supported by the chart anymore, their volume claims are kept but unused"
      fi
      delete_statefulset "$statefulset" "$selector"
    done
  fi
  if [ -n "$(annotation pvc "$claim" "$PENDING_ANNOTATION")" ]; then
    run_pod database-pod.yaml "$DB_FULLNAME-migration" "$claim" database-bitnami-volume.sh
    annotate pvc "$claim" "$PENDING_ANNOTATION"
  fi
}
