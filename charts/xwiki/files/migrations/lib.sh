#!/bin/sh
# Functions shared by the migrations.
#
# Environment set by the job:
#   RELEASE_NAME, NAMESPACE, FULLNAME  the release being upgraded
#   CHART_VERSION                      version of the chart being installed
#   DB_TYPE, DB_FULLNAME               database deployed by the chart (mariadb, mysql or postgresql), empty with an external one
#   DB_MAJOR                           major version of the PostgreSQL image deployed by the chart, empty otherwise
#   SKIP                               identifiers of the migrations to skip, separated by spaces
#   STEP_TIMEOUT                       maximum duration of a step (e.g. waiting for a pod), in seconds

log() {
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

# kubectl in the namespace of the release
k() {
  kubectl --namespace "$NAMESPACE" "$@"
}

is_skipped() {
  for skipped in ${SKIP:-}; do
    [ "$skipped" = "$1" ] && return 0
  done
  return 1
}

# Prints the label selector of the pods of a StatefulSet, nothing when it does not exist.
# Usage: statefulset_selector <name>
statefulset_selector() {
  k get statefulset "$1" --ignore-not-found \
    -o go-template='{{ range $k, $v := .spec.selector.matchLabels }}{{ $k }}={{ $v }},{{ end }}' | sed 's/,$//'
}

# Prints the value of an environment variable of the first container of a StatefulSet, nothing when it (or the
# StatefulSet) does not exist.
# Usage: statefulset_env <name> <variable>
statefulset_env() {
  k get statefulset "$1" --ignore-not-found \
    -o go-template="{{ with index .spec.template.spec.containers 0 }}{{ range .env }}{{ if eq .name \"$2\" }}{{ .value }}{{ end }}{{ end }}{{ end }}"
}

# Deletes a StatefulSet without its pods nor its volume claims (e.g. to recreate it with immutable fields changed, or to
# change the data of its volume: "helm upgrade" creates it again), then stops its pods.
# Usage: delete_statefulset <name> <label selector of its pods>
delete_statefulset() {
  log "Deleting the StatefulSet $1 (its volume claims are kept)"
  # The orphan cascade also removes the references from the volume claims to the StatefulSet, so they are kept whatever
  # its persistentVolumeClaimRetentionPolicy
  k delete statefulset "$1" --cascade=orphan --ignore-not-found --wait --timeout="${STEP_TIMEOUT}s"
  k delete controllerrevisions --selector "$2" --ignore-not-found
  log "Stopping the pods of $1"
  k delete pods --selector "$2" --ignore-not-found --wait --timeout="${STEP_TIMEOUT}s"
}

# Runs a pod built from a template of the migrations config map until it terminates, then deletes it. The template
# mounts the volume claim and runs the script, the pod is kept when it fails. The logs of the pod are printed and kept
# in the file $RUN_POD_LOG (e.g. for the script to return values).
# Usage: run_pod <template> <pod name> <volume claim> <script>
RUN_POD_LOG=/tmp/run_pod.log
run_pod() {
  log "Running $4 in the pod $2 (volume claim $3)"
  k delete pod "$2" --ignore-not-found --wait --timeout="${STEP_TIMEOUT}s"
  sed -e "s|__NAME__|$2|g" -e "s|__CLAIM__|$3|g" -e "s|__SCRIPT__|$4|g" "$MIGRATIONS_DIR/$1" | k create -f -
  deadline=$(($(date +%s) + STEP_TIMEOUT))
  while :; do
    phase=$(k get pod "$2" -o jsonpath='{.status.phase}')
    case "$phase" in
      Succeeded | Failed) break ;;
    esac
    if [ "$(date +%s)" -ge "$deadline" ]; then
      k describe pod "$2" || true
      phase="not finished after ${STEP_TIMEOUT}s"
      break
    fi
    sleep 5
  done
  k logs "$2" > "$RUN_POD_LOG" 2>&1 || true
  sed "s/^/  [$2] /" "$RUN_POD_LOG"
  if [ "$phase" != Succeeded ]; then
    fail "The pod $2 failed ($phase), it is kept for investigation and deleted by the next run"
  fi
  k delete pod "$2" --wait --timeout="${STEP_TIMEOUT}s"
}

# Marks a resource with an annotation (e.g. a migration in progress), the value is removed when empty.
# Usage: annotate <resource> <name> <annotation> [value]
annotate() {
  if [ -n "${4:-}" ]; then
    k annotate "$1" "$2" "$3=$4" --overwrite
  else
    k annotate "$1" "$2" "$3-"
  fi
}

# Prints the value of an annotation of a resource, nothing when it (or the resource) does not exist.
# Usage: annotation <resource> <name> <annotation>
annotation() {
  k get "$1" "$2" --ignore-not-found -o "jsonpath={.metadata.annotations.$(echo "$3" | sed 's/\./\\./g')}"
}
