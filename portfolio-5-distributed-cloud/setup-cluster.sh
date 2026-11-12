#!/bin/bash
# Builds a two-node PostgreSQL cluster for Ebute Fresh on this machine:
#   primary  on port 5440 (takes all reads and writes)
#   replica  on port 5441 (streaming copy of the primary, read only)
#
#   ./setup-cluster.sh > setup-cluster.out 2>&1
#
# Both data directories go under $BASE (default ~/ebute-cluster). The main
# PostgreSQL server on 5432 used in portfolios 1 to 3 is not touched.
# Running this again stops both nodes and starts from scratch.

set -eo pipefail
cd "$(dirname "$0")"

BASE=${BASE:-$HOME/ebute-cluster}
PRIMARY=$BASE/primary
REPLICA=$BASE/replica

for d in "$PRIMARY" "$REPLICA"; do
    if [ -f "$d/postmaster.pid" ]; then
        pg_ctl -D "$d" -m immediate stop > /dev/null
    fi
done
rm -rf "$BASE"
mkdir -p "$BASE"

echo "== 1. Create the primary"
initdb -D "$PRIMARY" --auth=trust -E UTF8 --locale=C > /dev/null
cat >> "$PRIMARY/postgresql.conf" <<'EOF'

# Ebute Fresh primary
port = 5440
cluster_name = 'ebute_primary'
timezone = 'Africa/Lagos'
wal_level = replica             # the default, written out because replication needs it
max_wal_senders = 5
EOF
pg_ctl -D "$PRIMARY" -l "$BASE/primary.log" -w start

psql -X -p 5440 -d postgres -q -c "CREATE ROLE replicator WITH REPLICATION LOGIN;"
createdb -p 5440 ebute_fresh
psql -X -p 5440 -d ebute_fresh -q -v ON_ERROR_STOP=1 \
     -c "SET client_min_messages = warning;" \
     -f ../portfolio-1-database-design/schema.sql \
     -f ../portfolio-1-database-design/sample-data.sql
psql -X -p 5440 -d ebute_fresh -c "SELECT count(*) AS lots, sum(qty_remaining) AS units_in_stock FROM produce_lot;"

echo "== 2. Clone it into a replica"
# -R writes standby.signal and primary_conninfo, so the copy starts as a standby.
# -C -S creates a replication slot, so the primary keeps any WAL the replica
#  has not received yet, even if the replica is down for a while.
pg_basebackup -h localhost -p 5440 -U replicator -D "$REPLICA" \
              -R -X stream -C -S ebute_replica_slot -v 2>&1 | sed 's/^/   /'
cat >> "$REPLICA/postgresql.conf" <<'EOF'

# Ebute Fresh replica (later settings override the primary's copied above)
port = 5441
cluster_name = 'ebute_replica'
hot_standby = on                # allow read-only queries while replaying
EOF
echo "   pg_basebackup set the replica to connect to the primary as:"
grep primary_conninfo "$REPLICA/postgresql.auto.conf" | grep -oE "(user|host|port)=[^ ]+" | paste -sd' ' - | sed "s/^/   /"
ls "$REPLICA" | grep signal | sed "s/^/   file present: /"
pg_ctl -D "$REPLICA" -l "$BASE/replica.log" -w start

echo "== 3. Check both nodes"
sleep 1
psql -X -p 5440 -d ebute_fresh -c "
SELECT current_setting('cluster_name') AS node, pg_is_in_recovery() AS read_only;" \
     -c "
SELECT application_name, client_addr, state, sync_state, sent_lsn, replay_lsn
FROM pg_stat_replication;"
psql -X -p 5441 -d ebute_fresh -c "
SELECT current_setting('cluster_name') AS node, pg_is_in_recovery() AS read_only;" \
     -c "
SELECT status, sender_host, sender_port, slot_name FROM pg_stat_wal_receiver;" \
     -c "SELECT count(*) AS lots, sum(qty_remaining) AS units_in_stock FROM produce_lot;"
