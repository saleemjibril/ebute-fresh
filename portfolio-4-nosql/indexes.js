// Indexes for Q1, Q2, Q4, Q5 and Q6. Q3 reads one order by _id, which is
// always indexed.
//
//   mongosh --quiet ebute_fresh indexes.js > indexes.out

// Q1: lots that still have stock, by commodity and grade, oldest first.
// Partial, like produce_lot_in_stock_idx in portfolio 2: most lots are
// empty, so they are left out of the index.
db.lots.createIndex(
  { "commodity.id": 1, grade: 1, received_at: 1 },
  { name: "lots_in_stock", partialFilterExpression: { qty_remaining: { $gt: 0 } } });

// Q2 and Q4: a farmer's lots. Q2 uses the first field only.
db.lots.createIndex(
  { "farmer.id": 1, "commodity.id": 1, received_at: 1 },
  { name: "lots_farmer" });

// Q6: stock by best-before date.
db.lots.createIndex(
  { best_before: 1 },
  { name: "lots_best_before", partialFilterExpression: { qty_remaining: { $gt: 0 } } });

// Q5: orders by status and delivery date.
db.orders.createIndex(
  { status: 1, delivery_date: 1 },
  { name: "orders_status_delivery" });

for (const c of ["lots", "orders"]) {
  const s = db[c].stats({ indexDetails: false });
  print("\n" + c + " indexes:");
  for (const [name, bytes] of Object.entries(s.indexSizes))
    print("  " + name.padEnd(24) + (bytes / 1024).toFixed(0).padStart(8) + " kB");
}
