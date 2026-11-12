# Copies the Ebute Fresh data from PostgreSQL (portfolio 2 data set) into
# MongoDB, reshaped into documents.
#
#   python3 load-from-postgres.py > load-from-postgres.out
#
# Needs psycopg2 and pymongo, PostgreSQL with the portfolio 2 data in
# ebute_fresh, and MongoDB running as a replica set on localhost:27017
# (see README). The four collections are dropped and rebuilt each time.
#
# Collections:
#   lots       one document per lot, with the allocations made from it
#   orders     one document per order, with its lines, allocations and payments
#   farmers    farmer details with their payouts
#   customers  customer details

import datetime
import time
from collections import defaultdict

import psycopg2
import psycopg2.extras
from bson.decimal128 import Decimal128
from pymongo import MongoClient

BATCH = 10000
LAGOS = datetime.timezone(datetime.timedelta(hours=1))   # no daylight saving in Nigeria


def day(d):
    """BSON has no date-only type, so dates are stored as midnight UTC."""
    return datetime.datetime(d.year, d.month, d.day, tzinfo=datetime.timezone.utc)


def money(x):
    return Decimal128(x)


def rows(pg, sql):
    cur = pg.cursor(name="c%d" % time.monotonic_ns(),
                    cursor_factory=psycopg2.extras.RealDictCursor)
    cur.itersize = 20000
    cur.execute(sql)
    yield from cur
    cur.close()


def insert_all(coll, docs):
    batch = []
    for d in docs:
        batch.append(d)
        if len(batch) == BATCH:
            coll.insert_many(batch, ordered=False)
            batch = []
    if batch:
        coll.insert_many(batch, ordered=False)


start = time.time()
pg = psycopg2.connect(dbname="ebute_fresh")
db = MongoClient("mongodb://localhost:27017/?replicaSet=rs0").ebute_fresh
for name in ("lots", "orders", "farmers", "customers"):
    db[name].drop()

# ---- customers -------------------------------------------------------------
customers = {}
for r in rows(pg, "SELECT * FROM customer ORDER BY customer_id"):
    doc = {"_id": r["customer_id"],
           "business_name": r["business_name"],
           "type": r["customer_type"],
           "contact_name": r["contact_name"],
           "phone": r["phone"],
           "address": r["address"],
           "lga": r["lga"]}
    if r["email"]:                      # left out rather than stored as null
        doc["email"] = r["email"]
    customers[r["customer_id"]] = doc
insert_all(db.customers, customers.values())

# ---- farmers, with their payouts embedded -----------------------------------
payouts = defaultdict(list)
for r in rows(pg, "SELECT * FROM farmer_payout ORDER BY payout_id"):
    payouts[r["farmer_id"]].append({"payout_id": r["payout_id"],
                                    "amount": money(r["amount"]),
                                    "paid_at": r["paid_at"],
                                    "bank_ref": r["bank_ref"]})


def farmer_docs():
    for r in rows(pg, """
            SELECT f.*, cc.centre_name, st.state_name
            FROM farmer f
            JOIN collection_centre cc ON cc.centre_id = f.home_centre_id
            JOIN state st             ON st.state_code = cc.state_code
            ORDER BY f.farmer_id"""):
        doc = {"_id": r["farmer_id"],
               "first_name": r["first_name"],
               "last_name": r["last_name"],
               "phone": r["phone"],
               "home_centre": {"id": r["home_centre_id"], "name": r["centre_name"],
                               "state": r["state_name"]},
               "registered_on": day(r["registered_on"]),
               "payouts": payouts.pop(r["farmer_id"], [])}
        if r["bank_name"]:
            doc["bank"] = {"name": r["bank_name"], "account_number": r["account_number"]}
        yield doc


insert_all(db.farmers, farmer_docs())

# ---- allocations, kept from both sides ---------------------------------------
# lot_side[lot_id]            -> what the lot document needs (who got the produce)
# order_side[(order, line)]   -> what the order document needs (where it came from)
lot_side = defaultdict(list)
order_side = defaultdict(list)
for r in rows(pg, """
        SELECT a.order_id, a.line_no, a.lot_id, a.quantity,
               o.customer_id, o.delivery_date,
               l.farmer_id, f.first_name || ' ' || f.last_name AS farmer_name,
               l.received_at, l.farm_gate_price, cc.centre_name, st.state_name
        FROM allocation a
        JOIN sales_order o        ON o.order_id = a.order_id
        JOIN produce_lot l        ON l.lot_id = a.lot_id
        JOIN farmer f             ON f.farmer_id = l.farmer_id
        JOIN collection_centre cc ON cc.centre_id = l.centre_id
        JOIN state st             ON st.state_code = cc.state_code
        ORDER BY a.order_id, a.line_no, a.lot_id"""):
    cu = customers[r["customer_id"]]
    lot_side[r["lot_id"]].append({
        "order_id": r["order_id"], "line_no": r["line_no"], "qty": r["quantity"],
        "delivery_date": day(r["delivery_date"]),
        "customer": {"id": cu["_id"], "name": cu["business_name"], "phone": cu["phone"]}})
    order_side[(r["order_id"], r["line_no"])].append({
        "lot_id": r["lot_id"], "qty": r["quantity"],
        "farm_gate_price": money(r["farm_gate_price"]),
        "received_at": r["received_at"],
        "farmer": {"id": r["farmer_id"], "name": r["farmer_name"]},
        "centre": {"name": r["centre_name"], "state": r["state_name"]}})

# ---- lots -------------------------------------------------------------------
def lot_docs():
    for r in rows(pg, """
            SELECT l.*, c.commodity_name, c.unit, c.shelf_life_days,
                   cc.centre_name, st.state_name,
                   f.first_name || ' ' || f.last_name AS farmer_name,
                   s.full_name AS officer, p.paid_at
            FROM produce_lot l
            JOIN commodity c          ON c.commodity_id = l.commodity_id
            JOIN collection_centre cc ON cc.centre_id = l.centre_id
            JOIN state st             ON st.state_code = cc.state_code
            JOIN farmer f             ON f.farmer_id = l.farmer_id
            JOIN staff s              ON s.staff_id = l.received_by
            LEFT JOIN farmer_payout p ON p.payout_id = l.payout_id
            ORDER BY l.lot_id"""):
        yield {"_id": r["lot_id"],
               "commodity": {"id": r["commodity_id"], "name": r["commodity_name"],
                             "unit": r["unit"]},
               "grade": r["grade"],
               "farmer": {"id": r["farmer_id"], "name": r["farmer_name"]},
               "centre": {"id": r["centre_id"], "name": r["centre_name"],
                          "state": r["state_name"]},
               "received_by": {"id": r["received_by"], "name": r["officer"]},
               "received_at": r["received_at"],
               # stored, not derived on every read as in the SQL view
               "best_before": day(r["received_at"].astimezone(LAGOS).date()
                                  + datetime.timedelta(days=r["shelf_life_days"])),
               "qty_received": r["qty_received"],
               "qty_remaining": r["qty_remaining"],
               "farm_gate_price": money(r["farm_gate_price"]),
               "payout": ({"id": r["payout_id"], "paid_at": r["paid_at"]}
                          if r["payout_id"] else None),
               "allocations": lot_side.pop(r["lot_id"], [])}


insert_all(db.lots, lot_docs())

# ---- orders -----------------------------------------------------------------
lines = defaultdict(list)
for r in rows(pg, """
        SELECT ol.*, c.commodity_name
        FROM order_line ol JOIN commodity c ON c.commodity_id = ol.commodity_id
        ORDER BY ol.order_id, ol.line_no"""):
    lines[r["order_id"]].append({
        "line_no": r["line_no"],
        "commodity": {"id": r["commodity_id"], "name": r["commodity_name"]},
        "grade": r["grade"], "qty": r["quantity"], "unit_price": money(r["unit_price"]),
        "allocations": order_side.pop((r["order_id"], r["line_no"]), [])})

payments = defaultdict(list)
for r in rows(pg, "SELECT * FROM payment ORDER BY payment_id"):
    p = {"payment_id": r["payment_id"], "amount": money(r["amount"]),
         "method": r["method"], "paid_at": r["paid_at"]}
    if r["reference"]:
        p["reference"] = r["reference"]
    payments[r["order_id"]].append(p)


def order_docs():
    for r in rows(pg, """
            SELECT o.*, s.full_name AS taken_by_name
            FROM sales_order o JOIN staff s ON s.staff_id = o.taken_by
            ORDER BY o.order_id"""):
        cu = customers[r["customer_id"]]
        yield {"_id": r["order_id"],
               "customer": {"id": cu["_id"], "name": cu["business_name"],
                            "type": cu["type"], "lga": cu["lga"]},
               "taken_by": {"id": r["taken_by"], "name": r["taken_by_name"]},
               "placed_at": r["placed_at"],
               "delivery_date": day(r["delivery_date"]),
               "status": r["status"],
               "lines": lines.pop(r["order_id"], []),
               "payments": payments.pop(r["order_id"], [])}


insert_all(db.orders, order_docs())

# Anything left over would mean a row had nowhere to go.
assert not payouts and not lot_side and not order_side and not lines and not payments

# ---- check the copy ---------------------------------------------------------
print("Loaded in %.0f s\n" % (time.time() - start))
cur = pg.cursor()
checks = [
    ("customers", "SELECT count(*) FROM customer", db.customers.count_documents({})),
    ("farmers", "SELECT count(*) FROM farmer", db.farmers.count_documents({})),
    ("lots", "SELECT count(*) FROM produce_lot", db.lots.count_documents({})),
    ("orders", "SELECT count(*) FROM sales_order", db.orders.count_documents({})),
]
for coll, field, sql in [
        ("farmers", "payouts", "SELECT count(*) FROM farmer_payout"),
        ("lots", "allocations", "SELECT count(*) FROM allocation"),
        ("orders", "lines", "SELECT count(*) FROM order_line"),
        ("orders", "lines.allocations", "SELECT count(*) FROM allocation"),
        ("orders", "payments", "SELECT count(*) FROM payment")]:
    pipeline = [{"$unwind": "$" + p} for p in
                (["lines", "lines.allocations"] if field == "lines.allocations" else [field])]
    pipeline.append({"$count": "n"})
    n = next(db[coll].aggregate(pipeline))["n"]
    checks.append(("%s.%s" % (coll, field), sql, n))

print("%-26s %12s %12s" % ("", "PostgreSQL", "MongoDB"))
for label, sql, mongo_n in checks:
    cur.execute(sql)
    pg_n = cur.fetchone()[0]
    print("%-26s %12d %12d  %s" % (label, pg_n, mongo_n, "ok" if pg_n == mongo_n else "DIFFERENT"))

print("\nSize in MongoDB:")
for name in ("lots", "orders", "farmers", "customers"):
    s = db.command("collStats", name)
    print("  %-10s %9d documents, average %5d bytes, %6.1f MB stored (compressed)"
          % (name, s["count"], s["avgObjSize"], s["storageSize"] / 1e6))
