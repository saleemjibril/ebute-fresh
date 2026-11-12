# Runs Q1 to Q6 against PostgreSQL and MongoDB and checks that both give the
# same answer, row for row.
#
#   python3 compare-with-postgres.py > compare-with-postgres.out

import datetime
from decimal import Decimal

import psycopg2
from pymongo import MongoClient

pg = psycopg2.connect(dbname="ebute_fresh")
pg.cursor().execute("SET timezone = 'Africa/Lagos'")
db = MongoClient("mongodb://localhost:27017/?replicaSet=rs0").ebute_fresh
LAGOS = datetime.timezone(datetime.timedelta(hours=1))
UTC = datetime.timezone.utc


def sql(q):
    cur = pg.cursor()
    cur.execute(q)
    return [tuple(r) for r in cur.fetchall()]


def d(x):
    return x.to_decimal() if hasattr(x, "to_decimal") else Decimal(x)


def at(y, m, day, tz=UTC):
    return datetime.datetime(y, m, day, tzinfo=tz)


checks = []

# Q1
pg_rows = sql("""SELECT lot_id, qty_remaining FROM produce_lot
                 WHERE commodity_id = 1 AND grade = 'A' AND qty_remaining > 0
                 ORDER BY received_at LIMIT 10""")
mg_rows = [(x["_id"], x["qty_remaining"]) for x in db.lots.find(
    {"commodity.id": 1, "grade": "A", "qty_remaining": {"$gt": 0}}).sort("received_at", 1).limit(10)]
checks.append(("Q1 tomato A in stock", pg_rows, mg_rows))

# Q2
pg_rows = sql("""SELECT lot_id, qty_received * farm_gate_price FROM produce_lot
                 WHERE farmer_id = 124 AND payout_id IS NULL ORDER BY received_at""")
mg_rows = [(x["_id"], x["qty_received"] * d(x["farm_gate_price"])) for x in db.lots.find(
    {"farmer.id": 124, "payout": None}).sort("received_at", 1)]
checks.append(("Q2 unpaid lots", pg_rows, mg_rows))

# Q3
pg_rows = sql("""SELECT a.line_no, a.lot_id, a.quantity, l.farmer_id FROM allocation a
                 JOIN produce_lot l ON l.lot_id = a.lot_id
                 WHERE a.order_id = 240965 ORDER BY 1, 2""")
o = db.orders.find_one({"_id": 240965})
mg_rows = sorted((ln["line_no"], a["lot_id"], a["qty"], a["farmer"]["id"])
                 for ln in o["lines"] for a in ln["allocations"])
checks.append(("Q3 trace order", pg_rows, mg_rows))

# Q4
pg_rows = sql("""SELECT a.order_id, l.lot_id, a.quantity, o.customer_id FROM produce_lot l
                 JOIN allocation a ON a.lot_id = l.lot_id
                 JOIN sales_order o ON o.order_id = a.order_id
                 WHERE l.farmer_id = 1370 AND l.commodity_id = 1
                   AND l.received_at >= '2026-10-01' AND l.received_at < '2026-10-16'
                 ORDER BY 1, 2""")
mg_rows = sorted((a["order_id"], x["_id"], a["qty"], a["customer"]["id"]) for x in db.lots.find(
    {"farmer.id": 1370, "commodity.id": 1,
     "received_at": {"$gte": at(2026, 10, 1, LAGOS), "$lt": at(2026, 10, 16, LAGOS)}})
    for a in x["allocations"])
checks.append(("Q4 recall", pg_rows, mg_rows))

# Q5
pg_rows = sql("""SELECT to_char(o.delivery_date, 'YYYY-MM'), c.commodity_name, s.state_name,
                        sum(a.quantity), sum(a.quantity * ol.unit_price),
                        sum(a.quantity * (ol.unit_price - l.farm_gate_price))
                 FROM sales_order o
                 JOIN order_line ol ON ol.order_id = o.order_id
                 JOIN allocation a ON a.order_id = ol.order_id AND a.line_no = ol.line_no
                 JOIN produce_lot l ON l.lot_id = a.lot_id
                 JOIN collection_centre cc ON cc.centre_id = l.centre_id
                 JOIN state s ON s.state_code = cc.state_code
                 JOIN commodity c ON c.commodity_id = ol.commodity_id
                 WHERE o.status = 'delivered'
                   AND o.delivery_date >= '2026-07-01' AND o.delivery_date < '2026-10-01'
                 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3""")
mg_rows = [(g["_id"]["month"], g["_id"]["commodity"], g["_id"]["state"], g["units"],
            d(g["revenue"]), d(g["margin"])) for g in db.orders.aggregate([
    {"$match": {"status": "delivered",
                "delivery_date": {"$gte": at(2026, 7, 1), "$lt": at(2026, 10, 1)}}},
    {"$unwind": "$lines"}, {"$unwind": "$lines.allocations"},
    {"$group": {"_id": {"month": {"$dateToString": {"date": "$delivery_date", "format": "%Y-%m"}},
                        "commodity": "$lines.commodity.name",
                        "state": "$lines.allocations.centre.state"},
                "units": {"$sum": "$lines.allocations.qty"},
                "revenue": {"$sum": {"$multiply": ["$lines.allocations.qty", "$lines.unit_price"]}},
                "margin": {"$sum": {"$multiply": ["$lines.allocations.qty",
                           {"$subtract": ["$lines.unit_price", "$lines.allocations.farm_gate_price"]}]}}}},
    {"$sort": {"_id.month": 1, "_id.commodity": 1, "_id.state": 1}}])]
checks.append(("Q5 monthly sales and margin", pg_rows, mg_rows))

# Q6
pg_rows = sql("""SELECT lot_id, qty_remaining, best_before FROM lot_stock
                 WHERE qty_remaining > 0
                   AND best_before BETWEEN date '2026-11-10' AND date '2026-11-12'
                 ORDER BY best_before, lot_id""")
mg_rows = [(x["_id"], x["qty_remaining"], x["best_before"].date()) for x in db.lots.find(
    {"qty_remaining": {"$gt": 0},
     "best_before": {"$gte": at(2026, 11, 10), "$lte": at(2026, 11, 12)}}).sort([("best_before", 1), ("_id", 1)])]
checks.append(("Q6 near best-before", pg_rows, mg_rows))

print("%-30s %10s %10s" % ("", "PostgreSQL", "MongoDB"))
for name, a, b in checks:
    print("%-30s %10d %10d  %s" % (name, len(a), len(b), "same" if a == b else "DIFFERENT"))

total = sql("SELECT sum(quantity * unit_price) FROM order_line")[0][0]
mg_total = next(db.orders.aggregate([
    {"$unwind": "$lines"},
    {"$group": {"_id": None, "t": {"$sum": {"$multiply": ["$lines.qty", "$lines.unit_price"]}}}}]))["t"]
print("\nValue of every order line ever taken:")
print("  PostgreSQL %s\n  MongoDB    %s" % (total, d(mg_total)))
