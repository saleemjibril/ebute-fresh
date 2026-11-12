// The six portfolio 2 queries, answered from the document model.
//
//   mongosh --quiet ebute_fresh queries.js > queries-before-indexes.out
//   mongosh --quiet ebute_fresh indexes.js > indexes.out
//   mongosh --quiet ebute_fresh queries.js > queries-after-indexes.out
//
// For each query it prints the result, then how MongoDB ran it: the plan
// stages, keys and documents examined, and the median of five timed runs
// (after one warm-up run).

const LAGOS = (d) => new Date(d + "T00:00:00+01:00");
const UTC = (d) => new Date(d + "T00:00:00Z");

function stages(plan, out = []) {
  if (!plan || typeof plan !== "object") return out;
  if (plan.stage) out.push(plan.stage + (plan.indexName ? "(" + plan.indexName + ")" : ""));
  for (const k of ["queryPlan", "inputStage"]) stages(plan[k], out);
  (plan.inputStages || []).forEach((p) => stages(p, out));
  return out;
}

function findStats(x) {
  // explain() output differs between find and aggregate; look for the parts we need
  if (!x || typeof x !== "object") return null;
  if (x.executionStats && x.queryPlanner) return x;
  for (const v of Object.values(x)) {
    const r = Array.isArray(v) ? v.map(findStats).find(Boolean) : findStats(v);
    if (r) return r;
  }
  return null;
}

function median(fn) {
  fn();
  const t = [];
  for (let i = 0; i < 5; i++) {
    const s = performance.now();
    fn();
    t.push(performance.now() - s);
  }
  t.sort((a, b) => a - b);
  return t[2];
}

function show(title, run, explain) {
  print("\n==== " + title + " ====");
  const result = run();
  if (result.length > 12) {
    print(result.length + " documents, first 10:");
    result.slice(0, 10).forEach((d) => print("  " + EJSON.stringify(d, { relaxed: true })));
  } else {
    result.forEach((d) => print("  " + EJSON.stringify(d, { relaxed: true })));
    print("(" + result.length + " documents)");
  }
  const s = findStats(explain());
  const e = s.executionStats;
  print("-- plan: " + stages(s.queryPlanner.winningPlan).join(" <- "));
  print("-- keys examined " + e.totalKeysExamined + ", documents examined " +
        e.totalDocsExamined + ", returned " + e.nReturned);
  print("-- median of 5 runs: " + median(run).toFixed(2) + " ms");
}

// Q1 --------------------------------------------------------------------------
const q1 = () => db.lots.find(
  { "commodity.id": 1, grade: "A", qty_remaining: { $gt: 0 } },
  { "centre.name": 1, qty_remaining: 1, received_at: 1, best_before: 1 })
  .sort({ received_at: 1 }).limit(10);
show("Q1. Grade A tomato in stock, oldest first (sales desk)",
     () => q1().toArray(), () => q1().explain("executionStats"));

// Q2 --------------------------------------------------------------------------
const q2 = () => db.lots.find(
  { "farmer.id": 124, payout: null },
  { "commodity.name": 1, grade: 1, qty_received: 1, farm_gate_price: 1, received_at: 1,
    amount_due: { $multiply: ["$qty_received", "$farm_gate_price"] } })
  .sort({ received_at: 1 });
show("Q2. Unpaid lots for farmer 124 (finance, Friday payout run)",
     () => q2().toArray(), () => q2().explain("executionStats"));

// Q3 --------------------------------------------------------------------------
// One document holds the whole answer: no joins.
const q3 = [
  { $match: { _id: 240965 } },
  { $unwind: "$lines" },
  { $unwind: "$lines.allocations" },
  { $project: { _id: 0, line_no: "$lines.line_no", commodity: "$lines.commodity.name",
                grade: "$lines.grade", qty: "$lines.allocations.qty",
                lot_id: "$lines.allocations.lot_id",
                received: { $dateToString: { date: "$lines.allocations.received_at",
                                             format: "%Y-%m-%d", timezone: "+01:00" } },
                farmer: "$lines.allocations.farmer.name",
                centre: "$lines.allocations.centre.name" } },
  { $sort: { line_no: 1, lot_id: 1 } }];
show("Q3. Trace order 240965 back to the farmers who supplied it",
     () => db.orders.aggregate(q3).toArray(),
     () => db.orders.explain("executionStats").aggregate(q3));

// Q4 --------------------------------------------------------------------------
// The reverse of Q3, answered from the lots side, where the customers are embedded.
const q4 = [
  { $match: { "farmer.id": 1370, "commodity.id": 1,
              received_at: { $gte: LAGOS("2026-10-01"), $lt: LAGOS("2026-10-16") } } },
  { $unwind: "$allocations" },
  { $project: { _id: 0, customer: "$allocations.customer.name",
                phone: "$allocations.customer.phone", order_id: "$allocations.order_id",
                delivery_date: { $dateToString: { date: "$allocations.delivery_date",
                                                  format: "%Y-%m-%d" } },
                lot_id: "$_id", qty: "$allocations.qty" } },
  { $sort: { delivery_date: 1, customer: 1 } }];
show("Q4. Recall: who received tomatoes from farmer 1370, 1 to 15 October 2026",
     () => db.lots.aggregate(q4).toArray(),
     () => db.lots.explain("executionStats").aggregate(q4));

// Q5 --------------------------------------------------------------------------
const q5 = [
  { $match: { status: "delivered",
              delivery_date: { $gte: UTC("2026-07-01"), $lt: UTC("2026-10-01") } } },
  { $unwind: "$lines" },
  { $unwind: "$lines.allocations" },
  { $group: {
      _id: { month: { $dateToString: { date: "$delivery_date", format: "%Y-%m" } },
             commodity: "$lines.commodity.name",
             state: "$lines.allocations.centre.state" },
      units: { $sum: "$lines.allocations.qty" },
      revenue: { $sum: { $multiply: ["$lines.allocations.qty", "$lines.unit_price"] } },
      margin: { $sum: { $multiply: ["$lines.allocations.qty",
                  { $subtract: ["$lines.unit_price", "$lines.allocations.farm_gate_price"] }] } } } },
  { $sort: { "_id.month": 1, "_id.commodity": 1, "_id.state": 1 } }];
show("Q5. Sales and margin by month, commodity and source state, July to September 2026",
     () => db.orders.aggregate(q5).toArray(),
     () => db.orders.explain("executionStats").aggregate(q5));

// Q6 --------------------------------------------------------------------------
const q6 = () => db.lots.find(
  { qty_remaining: { $gt: 0 },
    best_before: { $gte: UTC("2026-11-10"), $lte: UTC("2026-11-12") } },
  { "commodity.name": 1, grade: 1, "centre.name": 1, qty_remaining: 1, best_before: 1 })
  .sort({ best_before: 1, _id: 1 });
show("Q6. Stock reaching best-before in the next two days, as at 10 November 2026",
     () => q6().toArray(), () => q6().explain("executionStats"));
