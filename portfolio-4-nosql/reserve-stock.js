// confirm_order from portfolio 3, rewritten for the document model.
//
// Reserving stock now changes two kinds of document: each lot it takes from
// (qty_remaining and the lot's allocations), and the order (its allocations
// and status). The allocations are stored on both sides, so the two must
// change together. That needs a multi-document transaction.
//
// Run by run-reserve.sh as two sessions, A and B, at the same time:
//   mongosh --quiet ebute_fresh --eval 'const WHO = "A", ORDER = 246808' reserve-stock.js

function note(msg) {
  const t = new Date();
  const hms = new Date(t.getTime() + 3600 * 1000).toISOString().slice(11, 23);  // Lagos time
  print(hms + "|" + WHO + "|" + msg);
}

function confirmOrder(orderId, holdMs) {
  const session = db.getMongo().startSession();
  const lots = session.getDatabase("ebute_fresh").lots;
  const orders = session.getDatabase("ebute_fresh").orders;

  for (let attempt = 1; attempt <= 30; attempt++) {
    session.startTransaction({ readConcern: { level: "snapshot" },
                               writeConcern: { w: "majority" } });
    try {
      const order = orders.findOne({ _id: orderId });
      if (order.status !== "pending") throw new Error("order " + orderId + " is already " + order.status);

      // same rule as portfolio 3: handle lines in commodity and grade order
      const lines = order.lines.slice().sort((a, b) =>
        a.commodity.id - b.commodity.id || a.grade.localeCompare(b.grade));
      for (const line of lines) {
        let needed = line.qty;
        line.allocations = [];
        const cursor = lots.find({ "commodity.id": line.commodity.id, grade: line.grade,
                                   qty_remaining: { $gt: 0 } })
                           .sort({ received_at: 1, _id: 1 }).toArray();
        for (const lot of cursor) {
          const take = Math.min(needed, lot.qty_remaining);
          note("order " + orderId + ": lot " + lot._id + " shows " + lot.qty_remaining +
               " left, taking " + take);
          lots.updateOne({ _id: lot._id }, {
            $inc: { qty_remaining: NumberInt(-take) },
            $push: { allocations: { order_id: orderId, line_no: line.line_no, qty: NumberInt(take),
                                    delivery_date: order.delivery_date,
                                    customer: { id: order.customer.id, name: order.customer.name } } } });
          line.allocations.push({ lot_id: lot._id, qty: NumberInt(take),
                                  farm_gate_price: lot.farm_gate_price, received_at: lot.received_at,
                                  farmer: lot.farmer, centre: { name: lot.centre.name, state: lot.centre.state } });
          needed -= take;
          if (needed === 0) break;
        }
        if (needed > 0) throw new Error("not enough stock for order " + orderId +
                                        " line " + line.line_no + ": short by " + needed);
      }
      orders.updateOne({ _id: orderId }, { $set: { status: "confirmed", lines: lines.sort((a, b) => a.line_no - b.line_no) } });

      if (holdMs) { note("order " + orderId + ": printing delivery note, not committed yet"); sleep(holdMs); }
      session.commitTransaction();
      note("order " + orderId + ": COMMIT (attempt " + attempt + ")");
      return;
    } catch (e) {
      try { session.abortTransaction(); } catch (_) { /* already aborted */ }
      if (e.hasErrorLabel && e.hasErrorLabel("TransientTransactionError")) {
        note("order " + orderId + ": " + e.codeName + ", transaction aborted, retrying");
        sleep(250);
        continue;
      }
      note("order " + orderId + ": ERROR " + e.message);
      return;
    }
  }
}

if (WHO === "B") sleep(300);          // B starts 0.3 s after A
note("confirming order " + ORDER);
confirmOrder(ORDER, WHO === "A" ? 1500 : 0);
