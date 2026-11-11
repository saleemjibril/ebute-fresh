-- Two years of generated trading history for the performance tests.
--
-- Load order:
--   psql -d ebute_fresh -f ../portfolio-1-database-design/schema.sql \
--                       -f ../portfolio-1-database-design/sample-data.sql \
--                       -f generate-data.sql
--
-- The history runs from 4 November 2024 to 31 October 2026, so it ends just
-- before the sample week in Portfolio 1 (2 to 9 November 2026). The sample
-- rows keep their IDs; generated rows come after them.
--
-- setseed makes the output the same every time it is run.

\timing on
\set ON_ERROR_STOP on
SET timezone = 'Africa/Lagos';

BEGIN;
SELECT setseed(0.2026);


-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------

-- Monthly price list going back to November 2024. Prices were about 2% lower
-- for each month further back, rounded to the nearest N50.
INSERT INTO commodity_price (commodity_id, grade, effective_from, selling_price)
SELECT p.commodity_id, p.grade,
       (date '2026-10-01' - make_interval(months => m))::date,
       round(p.selling_price * power(0.98, m) / 50) * 50
FROM commodity_price p, generate_series(1, 23) m
WHERE p.effective_from = '2026-10-01';

-- Three more intake officers per centre (staff 10 to 24) and four more
-- sales staff (25 to 28).
INSERT INTO staff (full_name, role, centre_id, phone)
SELECT 'Intake Officer ' || g, 'intake_officer', 1 + (g - 1) % 5,
       '+23481' || lpad(g::text, 8, '0')
FROM generate_series(1, 15) g;

INSERT INTO staff (full_name, role, centre_id, phone)
SELECT 'Sales Officer ' || g, 'sales', NULL, '+23481' || lpad((100 + g)::text, 8, '0')
FROM generate_series(1, 4) g;

-- Farmer names by area, so Kadawa farmers have Hausa names and so on.
CREATE TEMP TABLE name_pool (centre_id int PRIMARY KEY, firsts text[], lasts text[]);
INSERT INTO name_pool VALUES
 (1, '{Musa,Aminu,Hadiza,Sani,Garba,Zainab,Ibrahim,Halima,Usman,Bello,Rabi,Yakubu}',
     '{Abdullahi,Garba,Sani,Usman,Danjuma,Ibrahim,Shehu,Lawan,Idris,Yusuf}'),
 (2, '{Danjuma,Ruth,Bitrus,Gyang,Pam,Rifkatu,Davou,Jang,Mary,Choji,Kaneng,Dalyop}',
     '{Gyang,Pam,Choji,Dung,Bot,Jambol,Dalyop,Davou,Jok,Mwadkon}'),
 (3, '{Terhemba,Msughter,Doosuur,Iveren,Aondona,Sewuese,Tersoo,Mnena,Orduen,Nguavese,Akaa,Seember}',
     '{Iorliam,Agber,Ikyaa,Tor,Akaa,Ugba,Orkar,Gbaa,Shija,Kwaghga}'),
 (4, '{Adewale,Funmilayo,Ayodele,Kehinde,Taiwo,Olawale,Bukola,Segun,Adebisi,Folake,Gbenga,Tunde}',
     '{Ogunleye,Adeyemi,Oyelaran,Akande,Ladipo,Ajani,Oladejo,Olaniyan,Adeoye,Ogundipe}'),
 (5, '{Olumide,Kehinde,Abiodun,Sola,Femi,Titilayo,Dapo,Yetunde,Lanre,Bisi,Wale,Remi}',
     '{Sodipo,Ogunbiyi,Onanuga,Adebanjo,Sonuga,Osinowo,Odusanya,Kuye,Shonibare,Adesina}');

-- 20,000 farmers. Kadawa is the biggest centre. 10% have no bank details.
INSERT INTO farmer (first_name, last_name, phone, home_centre_id, bank_name, account_number, registered_on)
SELECT np.firsts[1 + floor(r.r2 * 12)::int],
       np.lasts[1 + floor(r.r3 * 10)::int],
       '+23470' || lpad(r.g::text, 8, '0'),
       r.centre_id,
       CASE WHEN r.r4 < 0.9 THEN (ARRAY['First Bank','UBA','Zenith','Access','GTBank','Opay','Jaiz Bank','Wema'])[1 + floor(r.r5 * 8)::int] END,
       CASE WHEN r.r4 < 0.9 THEN lpad(floor(r.r6 * 1e10)::bigint::text, 10, '0') END,
       cc.opened_on + floor(r.r7 * 60)::int
FROM (
    SELECT g, random() AS r2, random() AS r3, random() AS r4, random() AS r5,
           random() AS r6, random() AS r7,
           CASE WHEN r1 < 0.30 THEN 1 WHEN r1 < 0.50 THEN 2 WHEN r1 < 0.70 THEN 3
                WHEN r1 < 0.85 THEN 4 ELSE 5 END AS centre_id
    FROM (SELECT g, random() AS r1 FROM generate_series(1, 20000) g) x
) r
JOIN name_pool np ON np.centre_id = r.centre_id
JOIN collection_centre cc ON cc.centre_id = r.centre_id
ORDER BY r.g;

-- 3,000 Lagos customers. A few order very often, most order now and then.
INSERT INTO customer (business_name, customer_type, contact_name, phone, email, address, lga)
SELECT (ARRAY['Mama','Iya','Royal','Golden','Fresh','City','Prime','Grace','Divine','Unity'])[1 + floor(r2 * 10)::int]
         || ' ' ||
       CASE ctype WHEN 'restaurant'  THEN (ARRAY['Kitchen','Eatery','Buka','Grills'])[1 + floor(r3 * 4)::int]
                  WHEN 'supermarket' THEN (ARRAY['Supermarket','Mart','Stores'])[1 + floor(r3 * 3)::int]
                  WHEN 'caterer'     THEN (ARRAY['Catering','Events','Chops'])[1 + floor(r3 * 3)::int]
                  ELSE (ARRAY['Foodstuff','Ventures','Enterprises'])[1 + floor(r3 * 3)::int] END
         || ' ' || g,
       ctype,
       (ARRAY['Adaeze','Bola','Chinedu','Damilola','Emeka','Funke','Ifeanyi','Kemi','Ngozi','Seun','Tolu','Yemi'])[1 + floor(r4 * 12)::int]
         || ' ' ||
       (ARRAY['Okafor','Adeyemi','Eze','Balogun','Nwachukwu','Ojo','Okeke','Salami','Obi','Lawal'])[1 + floor(r5 * 10)::int],
       '+23490' || lpad(g::text, 8, '0'),
       NULL,
       g || ' ' || (ARRAY['Allen Avenue','Awolowo Road','Herbert Macaulay Way','Ikorodu Road','Agege Motor Road','Adeola Odeku Street','Ogunlana Drive','Isheri Road'])[1 + floor(r6 * 8)::int],
       (ARRAY['Ikeja','Surulere','Eti-Osa','Lagos Island','Lagos Mainland','Kosofe','Alimosho','Oshodi-Isolo','Ikorodu','Apapa','Mushin','Agege','Amuwo-Odofin','Ojo'])[1 + floor(r7 * 14)::int]
FROM (
    SELECT g, random() AS r2, random() AS r3, random() AS r4, random() AS r5,
           random() AS r6, random() AS r7,
           CASE WHEN r1 < 0.45 THEN 'restaurant' WHEN r1 < 0.70 THEN 'trader'
                WHEN r1 < 0.80 THEN 'supermarket' ELSE 'caterer' END AS ctype
    FROM (SELECT g, random() AS r1 FROM generate_series(1, 3000) g) x
) r
ORDER BY g;


-- ---------------------------------------------------------------------------
-- Produce lots: 600,000 deliveries
-- ---------------------------------------------------------------------------

-- What each centre handles. A commodity listed twice comes in twice as often.
CREATE TEMP TABLE centre_mix (centre_id int PRIMARY KEY, commodities int[]);
INSERT INTO centre_mix VALUES
    (1, '{1,1,2,6}'),        -- Kadawa: tomato, onion, scotch bonnet
    (2, '{3,3,7,8,1}'),      -- Bukuru: Irish potato, cabbage, carrot, tomato
    (3, '{4}'),              -- Zaki Biam: yam
    (4, '{4,6,1}'),          -- Ogbomoso: yam, scotch bonnet, tomato
    (5, '{5}');              -- Ijebu-Ode: plantain

CREATE TEMP TABLE lot_stage AS
SELECT f.farmer_id,
       f.home_centre_id AS centre_id,
       cm.commodities[1 + floor(r.r2 * array_length(cm.commodities, 1))::int] AS commodity_id,
       CASE WHEN r.r3 < 0.3 THEN 'A' WHEN r.r3 < 0.8 THEN 'B' ELSE 'C' END AS grade,
       ((greatest(date '2024-11-04', f.registered_on)
          + floor(r.r4 * (date '2026-11-01' - greatest(date '2024-11-04', f.registered_on)))::int)
          + time '06:00' + r.r5 * interval '9 hours') AT TIME ZONE 'Africa/Lagos' AS received_at,
       r.r6 AS r_qty, r.r7 AS r_price, floor(r.r8 * 4)::int AS officer_slot
FROM (
    SELECT 13 + 1 + floor(random() * 20000)::int AS farmer_id,
           random() AS r2, random() AS r3, random() AS r4, random() AS r5,
           random() AS r6, random() AS r7, random() AS r8
    FROM generate_series(1, 600000)
) r
JOIN farmer f ON f.farmer_id = r.farmer_id
JOIN centre_mix cm ON cm.centre_id = f.home_centre_id;

INSERT INTO produce_lot (lot_id, farmer_id, centre_id, commodity_id, grade, qty_received,
                         qty_remaining, farm_gate_price, received_at, received_by)
OVERRIDING SYSTEM VALUE
SELECT 18 + row_number() OVER (ORDER BY s.received_at),
       s.farmer_id, s.centre_id, s.commodity_id, s.grade, q.qty, q.qty,
       round(cp.selling_price * (0.55 + s.r_price * 0.15) / 50) * 50,
       s.received_at,
       -- one of the four officers at the centre: the original (1 to 5) or 10 to 24
       CASE s.officer_slot WHEN 0 THEN s.centre_id ELSE 9 + s.centre_id + 5 * (s.officer_slot - 1) END
FROM lot_stage s
JOIN commodity c ON c.commodity_id = s.commodity_id
JOIN commodity_price cp
  ON cp.commodity_id = s.commodity_id AND cp.grade = s.grade
 AND cp.effective_from = date_trunc('month', s.received_at)::date
CROSS JOIN LATERAL (
    SELECT CASE c.unit WHEN 'crate' THEN 10 + floor(s.r_qty * 70)
                       WHEN 'bag'   THEN 5 + floor(s.r_qty * 35)
                       WHEN 'tuber' THEN 100 + floor(s.r_qty * 500)
                       ELSE 20 + floor(s.r_qty * 100) END::int AS qty
) q;


-- ---------------------------------------------------------------------------
-- Orders: up to 250,000, with 1 to 4 lines each
-- ---------------------------------------------------------------------------

CREATE TEMP TABLE order_stage AS
SELECT row_number() OVER () AS k, x.*,
       x.placed_at::date + 1 + (x.r_del < 0.3)::int AS delivery_date,
       x.r_status < 0.02 AS cancelled
FROM (
    SELECT 6 + 1 + floor(power(random(), 2) * 3000)::int AS customer_id,
           (ARRAY[6, 7, 25, 26, 27, 28])[1 + floor(random() * 6)::int] AS taken_by,
           ((date '2024-11-08' + floor(random() * 720)::int)
              + time '07:00' + random() * interval '11 hours') AT TIME ZONE 'Africa/Lagos' AS placed_at,
           random() AS r_del, random() AS r_status, 1 + floor(random() * random() * 4)::int AS n_lines,
           floor(random() * 8)::int AS first_commodity
    FROM generate_series(1, 250000)
) x;

-- Stepping through the commodities 3 at a time (mod 8) keeps them distinct
-- within an order.
CREATE TEMP TABLE line_stage AS
SELECT o.k, i AS line_no,
       1 + (o.first_commodity + (i - 1) * 3) % 8 AS commodity_id,
       -- cast to the column's own type; as text it stops the index on
       -- supply being used in the allocation join below
       (CASE WHEN random() < 0.3 THEN 'A' WHEN random() < 0.7 THEN 'B' ELSE 'C' END)::produce_grade AS grade,
       0.5 + random() AS weight,
       o.placed_at, o.delivery_date, o.cancelled
FROM order_stage o, generate_series(1, o.n_lines) i;

-- How much of each commodity and grade had arrived by the end of each day.
CREATE TEMP TABLE daily_supply AS
SELECT cg.commodity_id, cg.grade, d.day,
       sum(coalesce(x.qty, 0)) OVER (PARTITION BY cg.commodity_id, cg.grade ORDER BY d.day) AS cum
FROM (SELECT commodity_id, g::produce_grade AS grade FROM commodity, unnest('{A,B,C}'::text[]) g) cg
CROSS JOIN (SELECT generate_series(date '2024-11-01', date '2026-10-31', interval '1 day')::date AS day) d
LEFT JOIN (SELECT commodity_id, grade, received_at::date AS day, sum(qty_received) AS qty
           FROM produce_lot WHERE lot_id > 18
           GROUP BY 1, 2, 3) x
       ON x.commodity_id = cg.commodity_id AND x.grade = cg.grade AND x.day = d.day;

-- Line quantities follow supply. Produce takes about two days to reach
-- Lagos, so the lines delivered on day t share out whatever arrived at the
-- centres up to day t - 2 that earlier lines have not already taken, in
-- proportion to their weight. Each line ends up with a range [lo, hi) on the
-- running total for its commodity and grade.
CREATE TEMP TABLE line_range AS
WITH days AS (
    SELECT l.commodity_id, l.grade, l.delivery_date, ds.cum AS day_cum,
           coalesce(lag(ds.cum) OVER (PARTITION BY l.commodity_id, l.grade
                                      ORDER BY l.delivery_date), 0) AS prev_cum
    FROM (SELECT DISTINCT commodity_id, grade, delivery_date
          FROM line_stage WHERE NOT cancelled) l
    JOIN daily_supply ds
      ON ds.commodity_id = l.commodity_id AND ds.grade = l.grade
     AND ds.day = l.delivery_date - 2
),
pos AS (
    SELECT l.k, l.line_no, l.commodity_id, l.grade, l.delivery_date,
           round(d.prev_cum + (d.day_cum - d.prev_cum)
                 * sum(l.weight) OVER (PARTITION BY l.commodity_id, l.grade, l.delivery_date
                                       ORDER BY l.k, l.line_no)
                 / sum(l.weight) OVER (PARTITION BY l.commodity_id, l.grade, l.delivery_date))::bigint AS hi
    FROM line_stage l
    JOIN days d USING (commodity_id, grade, delivery_date)
    WHERE NOT l.cancelled
)
SELECT k, line_no, hi,
       coalesce(lag(hi) OVER (PARTITION BY commodity_id, grade
                              ORDER BY delivery_date, k, line_no), 0) AS lo
FROM pos;

-- Cancelled lines were never filled, so they just get a typical quantity.
-- Lines that would get nothing (for example plantain before Ijebu-Ode
-- opened in March 2025) are dropped, then the lines are renumbered.
CREATE TEMP TABLE final_line AS
SELECT l.k,
       row_number() OVER (PARTITION BY l.k ORDER BY l.line_no) AS line_no,
       l.commodity_id, l.grade, l.placed_at,
       coalesce(r.hi - r.lo, greatest(1, round(l.weight * a.avg_qty))::bigint) AS quantity,
       r.lo, r.hi
FROM line_stage l
LEFT JOIN line_range r USING (k, line_no)
JOIN (SELECT ls.commodity_id, ls.grade, avg(r2.hi - r2.lo) AS avg_qty
      FROM line_stage ls JOIN line_range r2 USING (k, line_no)
      GROUP BY 1, 2) a USING (commodity_id, grade)
WHERE l.cancelled OR r.hi > r.lo;

-- Orders left with no lines are dropped. The rest get their final IDs in
-- date order, after the 7 sample orders.
CREATE TEMP TABLE final_order AS
SELECT 7 + row_number() OVER (ORDER BY o.placed_at, o.k) AS order_id, o.*
FROM order_stage o
WHERE EXISTS (SELECT 1 FROM final_line f WHERE f.k = o.k);

INSERT INTO sales_order (order_id, customer_id, taken_by, placed_at, delivery_date, status)
OVERRIDING SYSTEM VALUE
SELECT order_id, customer_id, taken_by, placed_at, delivery_date,
       CASE WHEN cancelled THEN 'cancelled' ELSE 'delivered' END
FROM final_order;

INSERT INTO order_line (order_id, line_no, commodity_id, grade, quantity, unit_price)
SELECT o.order_id, f.line_no, f.commodity_id, f.grade, f.quantity, cp.selling_price
FROM final_line f
JOIN final_order o USING (k)
JOIN commodity_price cp
  ON cp.commodity_id = f.commodity_id AND cp.grade = f.grade
 AND cp.effective_from = date_trunc('month', f.placed_at)::date;


-- ---------------------------------------------------------------------------
-- Allocations: fill each line from the oldest stock first
-- ---------------------------------------------------------------------------
-- Lots are laid end to end as a running total per commodity and grade, in
-- the order they arrived. Where a line's range overlaps a lot's range, that
-- overlap is the quantity taken from the lot. This is the same rule the
-- sales desk follows (oldest lot first), done as one set-based query.
-- Because a line delivered on day t only reaches as far as the stock that
-- had arrived by day t - 2, no lot is used before it was received.

CREATE TEMP TABLE supply AS
SELECT lot_id, commodity_id, grade,
       sum(qty_received) OVER w - qty_received AS lo,
       sum(qty_received) OVER w AS hi
FROM produce_lot
WHERE lot_id > 18
WINDOW w AS (PARTITION BY commodity_id, grade ORDER BY received_at, lot_id);
CREATE INDEX ON supply (commodity_id, grade, lo);
ANALYZE supply;
ANALYZE final_line;
ANALYZE final_order;

-- Every row matches by construction, so the per-row trigger check is
-- switched off for the bulk insert and back on straight after.
ALTER TABLE allocation DISABLE TRIGGER allocation_match;

INSERT INTO allocation (order_id, line_no, lot_id, quantity)
SELECT o.order_id, f.line_no, s.lot_id,
       least(s.hi, f.hi) - greatest(s.lo, f.lo)
FROM final_line f
JOIN final_order o USING (k)
JOIN supply s
  ON s.commodity_id = f.commodity_id AND s.grade = f.grade
 AND s.lo >= f.lo - 600          -- no lot is bigger than 600 units
 AND s.lo < f.hi
 AND s.hi > f.lo
WHERE NOT o.cancelled;

ALTER TABLE allocation ENABLE TRIGGER allocation_match;

UPDATE produce_lot l
SET qty_remaining = l.qty_received - a.allocated
FROM (SELECT lot_id, sum(quantity) AS allocated
      FROM allocation WHERE order_id > 7 GROUP BY lot_id) a
WHERE a.lot_id = l.lot_id;


-- ---------------------------------------------------------------------------
-- Farmer payouts: every Friday, for that week's lots
-- ---------------------------------------------------------------------------
-- Only farmers with bank details are paid. A lot delivered on a Friday is
-- paid the following Friday.

CREATE TEMP TABLE lot_payday AS
SELECT l.lot_id, l.farmer_id, l.qty_received * l.farm_gate_price AS value,
       d + (12 - extract(isodow FROM d)::int) % 7
         + CASE WHEN extract(isodow FROM d) = 5 THEN 7 ELSE 0 END AS payday
FROM produce_lot l
JOIN farmer f ON f.farmer_id = l.farmer_id
CROSS JOIN LATERAL (SELECT l.received_at::date AS d) x
WHERE l.lot_id > 18 AND f.account_number IS NOT NULL;

DELETE FROM lot_payday WHERE payday >= date '2026-11-01';

CREATE TEMP TABLE payout_stage AS
SELECT 7 + row_number() OVER (ORDER BY payday, farmer_id) AS payout_id,
       farmer_id, payday, sum(value) AS amount
FROM lot_payday
GROUP BY farmer_id, payday;

INSERT INTO farmer_payout (payout_id, farmer_id, amount, paid_at, bank_ref, paid_by)
OVERRIDING SYSTEM VALUE
SELECT payout_id, farmer_id, amount,
       (payday + time '13:00' + (payout_id % 240) * interval '1 minute') AT TIME ZONE 'Africa/Lagos',
       'FT' || to_char(payday, 'YYMMDD') || lpad(payout_id::text, 7, '0'),
       8
FROM payout_stage;

UPDATE produce_lot l
SET payout_id = ps.payout_id
FROM lot_payday lp
JOIN payout_stage ps USING (farmer_id, payday)
WHERE lp.lot_id = l.lot_id;


-- ---------------------------------------------------------------------------
-- Customer payments
-- ---------------------------------------------------------------------------
-- 92% of delivered orders are paid in full, 5% have paid half, 3% nothing.
-- Cash payments have no reference.

INSERT INTO payment (order_id, amount, method, reference, paid_at)
SELECT o.order_id,
       CASE WHEN r.r1 < 0.92 THEN t.value ELSE round(t.value / 2, 2) END,
       m.method,
       CASE m.method WHEN 'transfer' THEN 'NIP' || lpad(o.order_id::text, 12, '0')
                     WHEN 'pos'      THEN 'POS-' || lpad(o.order_id::text, 11, '0') END,
       (o.delivery_date + time '09:00' + r.r3 * interval '72 hours') AT TIME ZONE 'Africa/Lagos'
FROM sales_order o
JOIN (SELECT order_id, sum(quantity * unit_price) AS value
      FROM order_line WHERE order_id > 7 GROUP BY order_id) t USING (order_id)
CROSS JOIN LATERAL (SELECT random() AS r1, random() AS r2, random() AS r3, o.order_id AS dep) r
CROSS JOIN LATERAL (
    SELECT CASE WHEN r.r2 < 0.70 THEN 'transfer' WHEN r.r2 < 0.95 THEN 'pos' ELSE 'cash' END AS method
) m
WHERE o.order_id > 7 AND o.status = 'delivered' AND r.r1 < 0.97;


-- ---------------------------------------------------------------------------
-- Tidy up
-- ---------------------------------------------------------------------------

SELECT setval(pg_get_serial_sequence('staff', 'staff_id'),         (SELECT max(staff_id) FROM staff));
SELECT setval(pg_get_serial_sequence('produce_lot', 'lot_id'),     (SELECT max(lot_id) FROM produce_lot));
SELECT setval(pg_get_serial_sequence('sales_order', 'order_id'),   (SELECT max(order_id) FROM sales_order));
SELECT setval(pg_get_serial_sequence('farmer_payout', 'payout_id'),(SELECT max(payout_id) FROM farmer_payout));

COMMIT;

VACUUM ANALYZE;

\echo
\echo Row counts after generation:
SELECT 'farmer' AS table_name, count(*) FROM farmer
UNION ALL SELECT 'customer', count(*) FROM customer
UNION ALL SELECT 'produce_lot', count(*) FROM produce_lot
UNION ALL SELECT 'farmer_payout', count(*) FROM farmer_payout
UNION ALL SELECT 'sales_order', count(*) FROM sales_order
UNION ALL SELECT 'order_line', count(*) FROM order_line
UNION ALL SELECT 'allocation', count(*) FROM allocation
UNION ALL SELECT 'payment', count(*) FROM payment;

SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;
