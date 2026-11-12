#!/bin/sh
# Two sales staff confirm orders for grade A tomato at the same moment.
#
#   ./run-reserve.sh > reserve-stock.out
#
# Resets the two demo orders (246808 and 246809), shows the stock, runs
# reserve-stock.js as session A and session B in parallel, merges their
# output by time, and shows the result.

set -e
cd "$(dirname "$0")"
tmp=$(mktemp -d)

mongosh --quiet ebute_fresh --eval '
const demo = [246808, 246809];
// undo any earlier run
for (const lot of db.lots.find({ "allocations.order_id": { $in: demo } }).toArray()) {
  const back = lot.allocations.filter(a => demo.includes(a.order_id)).reduce((s, a) => s + a.qty, 0);
  db.lots.updateOne({ _id: lot._id }, { $inc: { qty_remaining: NumberInt(back) },
                                        $pull: { allocations: { order_id: { $in: demo } } } });
}
db.orders.deleteMany({ _id: { $in: demo } });

const cust = (id) => { const c = db.customers.findOne({ _id: id });
                       return { id: c._id, name: c.business_name, type: c.type, lga: c.lga }; };
const line = { line_no: NumberInt(1), commodity: { id: 1, name: "Tomato" }, grade: "A",
               qty: NumberInt(30), unit_price: NumberDecimal("43000.00"), allocations: [] };
db.orders.insertMany([
  { _id: 246808, customer: cust(2), taken_by: { id: 6, name: "Chiamaka Obi" },
    placed_at: new Date("2026-11-12T09:10:00+01:00"), delivery_date: new Date("2026-11-13T00:00:00Z"),
    status: "pending", lines: [line], payments: [] },
  { _id: 246809, customer: cust(3), taken_by: { id: 7, name: "Femi Lawal" },
    placed_at: new Date("2026-11-12T09:12:00+01:00"), delivery_date: new Date("2026-11-13T00:00:00Z"),
    status: "pending", lines: [line], payments: [] }]);

print("Before: two pending orders for 30 crates of grade A tomato each.");
print("Oldest grade A tomato with stock:");
db.lots.find({ "commodity.id": 1, grade: "A", qty_remaining: { $gt: 0 } },
             { qty_remaining: 1, "centre.name": 1 }).sort({ received_at: 1, _id: 1 }).limit(2)
  .forEach(l => print("  lot " + l._id + " (" + l.centre.name + "): " + l.qty_remaining + " crates"));
print("");'

mongosh --quiet ebute_fresh --eval 'const WHO = "A", ORDER = 246808' reserve-stock.js > "$tmp/a" 2>&1 &
mongosh --quiet ebute_fresh --eval 'const WHO = "B", ORDER = 246809' reserve-stock.js > "$tmp/b" 2>&1 &
wait

python3 - "$tmp/a" "$tmp/b" <<'PY'
import re, sys
timed = re.compile(r'^(\d\d:\d\d:\d\d\.\d{3})\|([AB])\|(.*)$')
events = []
for path in sys.argv[1:]:
    for line in open(path):
        m = timed.match(line.rstrip("\n"))
        if m:
            events.append(m.groups())
        elif line.strip():
            events.append(("99", "?", line.rstrip()))
events.sort(key=lambda e: e[0])
def secs(t):
    h, m, s = t.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)
start = secs(events[0][0])
print("  time   session")
for t, who, msg in events:
    print("%6.2fs   %s   %s" % (secs(t) - start, who, msg) if who != "?" else "         " + msg)
PY

mongosh --quiet ebute_fresh --eval '
print("\nAfter:");
db.orders.find({ _id: { $in: [246808, 246809] } }).forEach(o =>
  print("  order " + o._id + " " + o.status + ": " +
        o.lines[0].allocations.map(a => a.qty + " from lot " + a.lot_id).join(", ")));
db.lots.find({ "allocations.order_id": { $in: [246808, 246809] } }).sort({ _id: 1 }).forEach(l =>
  print("  lot " + l._id + ": received " + l.qty_received + ", allocated " +
        l.allocations.reduce((s, a) => s + a.qty, 0) + " in total, " + l.qty_remaining + " left"));'

rm -r "$tmp"
