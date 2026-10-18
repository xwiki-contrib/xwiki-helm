#!/bin/sh
# Runs the migrations of the chart. It is executed by a Helm hook before the resources of the release are upgraded, to
# apply the changes between two versions of the chart that "helm upgrade" cannot apply by itself.
#
# A migration is a file named "<number>-<identifier>.sh" (executed in the order of the numbers) defining the functions:
#   migration_description  prints what the migration does
#   migration_needed       returns 0 when the migration has to be applied, found from the state of the release
#   migration_apply        applies the migration
# Migrations are executed again when "helm upgrade" is retried after a failure: they must be idempotent and detect a
# migration that was interrupted. They are executed in their own shell (with "set -eu") and can use lib.sh.
set -eu

MIGRATIONS_DIR=$(dirname "$0")
export MIGRATIONS_DIR
. "$MIGRATIONS_DIR/lib.sh"

if [ "${1:-}" = "--migration" ]; then
  . "$2"
  id=$(basename "$2" .sh)
  if migration_needed; then
    log "[$id] $(migration_description)"
    migration_apply
    log "[$id] Done"
  else
    log "[$id] Not needed"
  fi
  exit 0
fi

log "Running the migrations of the release $RELEASE_NAME (namespace $NAMESPACE) towards version $CHART_VERSION of the chart"
for migration in "$MIGRATIONS_DIR"/[0-9]*.sh; do
  [ -e "$migration" ] || continue
  id=$(basename "$migration" .sh)
  if is_skipped "$id"; then
    log "[$id] Skipped (migrations.skip)"
    continue
  fi
  # A new process, so that "set -e" applies to the migration
  sh "$0" --migration "$migration" || fail "[$id] Failed, the release was not upgraded. Fix the issue and run the upgrade again."
done
log "Migrations done"
