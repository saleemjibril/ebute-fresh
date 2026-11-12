// Schema validation on the lots collection, and what it cannot check.
//
//   mongosh --quiet ebute_fresh validation.js > validation.out
//
// MongoDB does not need a schema, but Ebute Fresh still needs the rules from
// portfolio 1. $jsonSchema covers types, required fields and ranges. $expr
// covers a rule across fields of the same document: qty_remaining must equal
// qty_received minus everything allocated. In PostgreSQL that rule was only
// partly enforced (a CHECK kept qty_remaining in range, see portfolio 3).
//
// Numbers typed in mongosh are doubles, so NumberInt() is used below. The
// loader writes Python ints, which are stored as int.

db.runCommand({
  collMod: "lots",
  validationLevel: "strict",
  validationAction: "error",
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["commodity", "grade", "farmer", "centre", "received_by", "received_at",
                 "best_before", "qty_received", "qty_remaining", "farm_gate_price", "allocations"],
      properties: {
        grade: { enum: ["A", "B", "C"] },
        qty_received: { bsonType: "int", minimum: 1 },
        qty_remaining: { bsonType: "int", minimum: 0 },
        farm_gate_price: { bsonType: "decimal", minimum: 0, exclusiveMinimum: true },
        received_at: { bsonType: "date" },
        farmer: { bsonType: "object", required: ["id", "name"] },
        allocations: {
          bsonType: "array",
          items: { bsonType: "object", required: ["order_id", "line_no", "qty"],
                   properties: { qty: { bsonType: "int", minimum: 1 } } } } } },
    $expr: { $eq: ["$qty_remaining",
                   { $subtract: ["$qty_received", { $sum: "$allocations.qty" }] }] } } });

const rule = db.getCollectionInfos({ name: "lots" })[0].options.validator;
print("Lots already loaded that break the rules: " + db.lots.countDocuments({ $nor: [rule] }));

function attempt(label, fn) {
  try {
    const r = fn();
    print("ACCEPTED  " + label + "  " + EJSON.stringify(r, { relaxed: true }));
  } catch (e) {
    const why = JSON.stringify(e.errInfo ? e.errInfo.details : e.message);
    print("REJECTED  " + label + "\n          " + e.message.split("\n")[0] +
          "\n          " + why.slice(0, 220) + (why.length > 220 ? "..." : ""));
  }
}

const good = {
  _id: 900001,
  commodity: { id: 1, name: "Tomato", unit: "crate" },
  grade: "A",
  farmer: { id: 2, name: "Aminu Danjuma" },
  centre: { id: 1, name: "Kadawa", state: "Kano" },
  received_by: { id: 1, name: "Kabiru Yusuf" },
  received_at: new Date("2026-11-12T07:05:00+01:00"),
  best_before: new Date("2026-11-19T00:00:00Z"),
  qty_received: NumberInt(40),
  qty_remaining: NumberInt(40),
  farm_gate_price: NumberDecimal("27000.00"),
  payout: null,
  allocations: []
};
const bad = (changes) => Object.assign({}, good, changes);

print("\n--- Inserts");
attempt("grade D", () => db.lots.insertOne(bad({ grade: "D" })));
attempt("negative stock", () => db.lots.insertOne(bad({ qty_remaining: NumberInt(-5) })));
attempt("no farmer", () => { const d = bad({}); delete d.farmer; return db.lots.insertOne(d); });
attempt("price as text", () => db.lots.insertOne(bad({ farm_gate_price: "27000" })));
attempt("remaining does not match allocations",
        () => db.lots.insertOne(bad({ allocations: [{ order_id: 246807, line_no: NumberInt(1),
                                                      qty: NumberInt(10) }] })));
attempt("valid lot", () => db.lots.insertOne(good));

print("\n--- Updates");
attempt("allocate 10 crates but forget to reduce qty_remaining",
        () => db.lots.updateOne({ _id: 900001 },
          { $push: { allocations: { order_id: 246807, line_no: NumberInt(1), qty: NumberInt(10) } } }));
attempt("allocate 10 crates and reduce qty_remaining in the same update",
        () => db.lots.updateOne({ _id: 900001 },
          { $push: { allocations: { order_id: 246807, line_no: NumberInt(1), qty: NumberInt(10) } },
            $inc: { qty_remaining: NumberInt(-10) } }));
attempt("allocate to an order that does not exist",
        () => db.lots.updateOne({ _id: 900001 },
          { $push: { allocations: { order_id: 999999999, line_no: NumberInt(1), qty: NumberInt(5) } },
            $inc: { qty_remaining: NumberInt(-5) } }));
print("Order 999999999 exists: " + (db.orders.countDocuments({ _id: 999999999 }) > 0));
print("Order 246807 exists, but its document knows nothing about lot 900001: " +
      (db.orders.countDocuments({ _id: 246807, "lines.allocations.lot_id": 900001 }) == 0));

db.lots.deleteOne({ _id: 900001 });
