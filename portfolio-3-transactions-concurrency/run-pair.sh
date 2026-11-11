#!/bin/sh
# Runs a two-session demo: NAME-a.sql and NAME-b.sql start at the same time
# as two separate psql connections. pg_sleep inside the scripts controls the
# order of events.
#
#   ./run-pair.sh 03-lost-update      -> writes 03-lost-update.out
#
# Each session prints timestamped lines through demo_note(). Errors from
# psql have no timestamp, so they are placed just before the next line from
# the same session. The two outputs are then merged by time.

set -e
name=${1:?usage: ./run-pair.sh demo-name}
db=ebute_fresh
tmp=$(mktemp -d)

psql -d "$db" -q -f setup.sql

psql -d "$db" -X -A -t -q -f "$name-a.sql" > "$tmp/a" 2>&1 &
psql -d "$db" -X -A -t -q -f "$name-b.sql" > "$tmp/b" 2>&1 &
wait

python3 - "$tmp/a" "$tmp/b" > "$name.out" <<'EOF'
import re, sys

timed = re.compile(r'^(\d\d:\d\d:\d\d\.\d{3})\|([AB])\|(.*)$')
events = []
for path, who in zip(sys.argv[1:], "AB"):
    pending = []
    last = "99:99:99.999"
    for line in open(path):
        line = line.rstrip("\n")
        if not line.strip():
            continue                      # blank rows from pg_sleep() etc.
        m = timed.match(line)
        if m:
            for p in pending:
                events.append((m.group(1), who, "   " + p))
            pending = []
            events.append((m.group(1), who, m.group(3)))
            last = m.group(1)
        else:
            pending.append(re.sub(r'^psql:[^:]+:\d+: ', '', line))
    for p in pending:
        events.append((last, who, "   " + p))

events.sort(key=lambda e: e[0])           # stable, so each session keeps its order
start = events[0][0]

def secs(t):
    h, m, s = t.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)

print("  time   session")
for t, who, msg in events:
    print("%6.2fs   %s   %s" % (secs(t) - secs(start), who, msg))
EOF

rm -r "$tmp"
cat "$name.out"
