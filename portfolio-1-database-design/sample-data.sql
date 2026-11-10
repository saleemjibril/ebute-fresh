-- Sample data for one week of trading, 2 to 9 November 2026.
-- Load straight after schema.sql, so the identity columns start at 1:
--   psql -d ebute_fresh -f schema.sql -f sample-data.sql
--
-- The IDs used in the foreign keys below depend on that insert order.

BEGIN;

INSERT INTO state VALUES
    ('KN', 'Kano'), ('PL', 'Plateau'), ('BN', 'Benue'),
    ('OY', 'Oyo'),  ('OG', 'Ogun'),    ('LA', 'Lagos');

INSERT INTO collection_centre (centre_name, town, state_code, opened_on) VALUES
    ('Kadawa',    'Kadawa',    'KN', '2023-02-01'),   -- 1
    ('Bukuru',    'Bukuru',    'PL', '2023-06-12'),   -- 2
    ('Zaki Biam', 'Zaki Biam', 'BN', '2024-01-15'),   -- 3
    ('Ogbomoso',  'Ogbomoso',  'OY', '2024-09-02'),   -- 4
    ('Ijebu-Ode', 'Ijebu-Ode', 'OG', '2025-03-10');   -- 5

INSERT INTO staff (full_name, role, centre_id, phone) VALUES
    ('Kabiru Yusuf',     'intake_officer', 1,    '+2348034417720'),  -- 1
    ('Joseph Dung',      'intake_officer', 2,    '+2348065512093'),  -- 2
    ('Iveren Tor',       'intake_officer', 3,    '+2347038821456'),  -- 3
    ('Bolaji Akande',    'intake_officer', 4,    '+2348139900412'),  -- 4
    ('Toyin Adebayo',    'intake_officer', 5,    '+2349057762318'),  -- 5
    ('Chiamaka Obi',     'sales',          NULL, '+2348023345671'),  -- 6
    ('Femi Lawal',       'sales',          NULL, '+2348101129864'),  -- 7
    ('Ngozi Eze',        'finance',        NULL, '+2347064458820'),  -- 8
    ('Tunde Bakare',     'manager',        NULL, '+2348037719045');  -- 9

-- Three farmers have not given bank details yet, so they cannot be paid.
INSERT INTO farmer (first_name, last_name, phone, home_centre_id, bank_name, account_number, registered_on) VALUES
    ('Musa',      'Abdullahi', '+2348036621904', 1, 'Jaiz Bank',  '0012348871', '2023-02-14'),  -- 1
    ('Aminu',     'Garba',     '+2348067734410', 1, 'UBA',        '2087734410', '2023-03-02'),  -- 2
    ('Hadiza',    'Sani',      '+2347031186625', 1, 'Access',     '0691186625', '2024-05-20'),  -- 3
    ('Danjuma',   'Gyang',     '+2348065590318', 2, 'First Bank', '3110590318', '2023-06-20'),  -- 4
    ('Ruth',      'Pam',       '+2348134471209', 2, 'Zenith',     '2214471209', '2023-08-01'),  -- 5
    ('Bitrus',    'Choji',     '+2349061128834', 2, NULL,         NULL,         '2025-10-11'),  -- 6
    ('Terhemba',  'Iorliam',   '+2348036047751', 3, 'GTBank',     '0136047751', '2024-01-22'),  -- 7
    ('Msughter',  'Agber',     '+2347067213390', 3, 'First Bank', '3047213390', '2024-02-05'),  -- 8
    ('Doosuur',   'Ikyaa',     '+2348159936402', 3, 'Opay',       '8159936402', '2025-07-19'),  -- 9
    ('Adewale',   'Ogunleye',  '+2348032268817', 4, 'Wema',       '0232268817', '2024-09-10'),  -- 10
    ('Funmilayo', 'Adeyemi',   '+2348107754091', 4, NULL,         NULL,         '2026-10-28'),  -- 11
    ('Olumide',   'Sodipo',    '+2348028819063', 5, 'Sterling',   '0068819063', '2025-03-18'),  -- 12
    ('Kehinde',   'Ogunbiyi',  '+2347045530187', 5, NULL,         NULL,         '2026-09-03');  -- 13

INSERT INTO commodity (commodity_name, unit, shelf_life_days) VALUES
    ('Tomato',          'crate', 7),    -- 1
    ('Onion',           'bag',   60),   -- 2
    ('Irish potato',    'bag',   30),   -- 3
    ('Yam',             'tuber', 90),   -- 4
    ('Plantain',        'bunch', 10),   -- 5
    ('Scotch bonnet',   'bag',   10),   -- 6
    ('Cabbage',         'bag',   14),   -- 7
    ('Carrot',          'bag',   21);   -- 8

-- Price list from 1 October, plus a tomato price rise on 7 November.
INSERT INTO commodity_price VALUES
    (1, 'A', '2026-10-01', 38000), (1, 'B', '2026-10-01', 32000), (1, 'C', '2026-10-01', 24000),
    (1, 'A', '2026-11-07', 42000), (1, 'B', '2026-11-07', 35000), (1, 'C', '2026-11-07', 26000),
    (2, 'A', '2026-10-01', 120000), (2, 'B', '2026-10-01', 100000), (2, 'C', '2026-10-01', 80000),
    (3, 'A', '2026-10-01', 55000), (3, 'B', '2026-10-01', 46000), (3, 'C', '2026-10-01', 36000),
    (4, 'A', '2026-10-01', 4500),  (4, 'B', '2026-10-01', 3500),  (4, 'C', '2026-10-01', 2500),
    (5, 'A', '2026-10-01', 9000),  (5, 'B', '2026-10-01', 7000),  (5, 'C', '2026-10-01', 5000),
    (6, 'A', '2026-10-01', 45000), (6, 'B', '2026-10-01', 40000), (6, 'C', '2026-10-01', 30000),
    (7, 'A', '2026-10-01', 22000), (7, 'B', '2026-10-01', 18000), (7, 'C', '2026-10-01', 13000),
    (8, 'A', '2026-10-01', 30000), (8, 'B', '2026-10-01', 25000), (8, 'C', '2026-10-01', 19000);

-- Friday payout for lots delivered from Monday to Wednesday.
INSERT INTO farmer_payout (farmer_id, amount, paid_at, bank_ref, paid_by) VALUES
    (1, 1776000, '2026-11-06 14:05+01', 'FT26110600118', 8),   -- 1: lots 1 and 4
    (2,  855000, '2026-11-06 14:07+01', 'FT26110600119', 8),   -- 2: lot 2
    (3, 2550000, '2026-11-06 14:09+01', 'FT26110600120', 8),   -- 3: lot 3
    (4, 1520000, '2026-11-06 14:12+01', 'FT26110600121', 8),   -- 4: lot 5
    (5,  360000, '2026-11-06 14:13+01', 'FT26110600122', 8),   -- 5: lot 6
    (7, 1120000, '2026-11-06 14:16+01', 'FT26110600123', 8),   -- 6: lot 8
    (8,  735000, '2026-11-06 14:18+01', 'FT26110600124', 8);   -- 7: lot 9

-- qty_remaining starts equal to qty_received and is corrected after the
-- allocations are loaded.
INSERT INTO produce_lot (farmer_id, centre_id, commodity_id, grade, qty_received, qty_remaining,
                         farm_gate_price, received_at, received_by, payout_id) VALUES
    (1,  1, 1, 'A',  60,  60, 24000, '2026-11-02 07:40+01', 1, 1),     -- 1
    (2,  1, 1, 'B',  45,  45, 19000, '2026-11-02 08:15+01', 1, 2),     -- 2
    (3,  1, 2, 'A',  30,  30, 85000, '2026-11-03 09:30+01', 1, 3),     -- 3
    (1,  1, 6, 'B',  12,  12, 28000, '2026-11-04 07:55+01', 1, 1),     -- 4
    (4,  2, 3, 'A',  40,  40, 38000, '2026-11-02 10:20+01', 2, 4),     -- 5
    (5,  2, 8, 'A',  20,  20, 18000, '2026-11-03 08:45+01', 2, 5),     -- 6
    (6,  2, 7, 'B',  25,  25, 12000, '2026-11-03 11:10+01', 2, NULL),  -- 7
    (7,  3, 4, 'A', 400, 400,  2800, '2026-11-02 12:00+01', 3, 6),     -- 8
    (8,  3, 4, 'B', 350, 350,  2100, '2026-11-04 13:25+01', 3, 7),     -- 9
    (10, 4, 6, 'A',  15,  15, 32000, '2026-11-05 08:05+01', 4, NULL),  -- 10
    (11, 4, 1, 'C',  30,  30, 12000, '2026-11-05 09:40+01', 4, NULL),  -- 11
    (12, 5, 5, 'A',  80,  80,  5500, '2026-11-05 07:15+01', 5, NULL),  -- 12
    (13, 5, 5, 'B',  60,  60,  4000, '2026-11-06 07:50+01', 5, NULL),  -- 13
    (2,  1, 1, 'A',  50,  50, 26000, '2026-11-07 07:35+01', 1, NULL),  -- 14
    (9,  3, 4, 'A', 300, 300,  2900, '2026-11-08 11:45+01', 3, NULL),  -- 15
    (4,  2, 3, 'B',  35,  35, 30000, '2026-11-08 10:05+01', 2, NULL),  -- 16
    (3,  1, 2, 'B',  25,  25, 70000, '2026-11-09 08:20+01', 1, NULL),  -- 17
    (12, 5, 5, 'A',  70,  70,  5800, '2026-11-09 07:10+01', 5, NULL);  -- 18

INSERT INTO customer (business_name, customer_type, contact_name, phone, email, address, lga) VALUES
    ('Iya Basira Foods',        'restaurant',  'Basirat Olawale',  '+2348023317764', NULL,                       '14 Adeniran Ogunsanya St, Surulere', 'Surulere'),     -- 1
    ('GreenBasket Supermarket', 'supermarket', 'Ifeoma Nwosu',     '+2349014452290', 'purchasing@greenbasket.ng', 'Admiralty Way, Lekki Phase 1',       'Eti-Osa'),      -- 2
    ('Kemi''s Events Catering', 'caterer',     'Kemi Adeleke',     '+2348187730025', 'bookings@kemisevents.ng',  '7 Allen Avenue, Ikeja',              'Ikeja'),        -- 3
    ('Sule Onion Depot',        'trader',      'Sule Danladi',     '+2348036650119', NULL,                       'Shed 22, Mile 12 Market',            'Kosofe'),       -- 4
    ('Lagoon View Supermarket', 'supermarket', 'Gbenga Martins',   '+2347012289543', 'orders@lagoonview.ng',      '3 Broad Street, Lagos Island',       'Lagos Island'), -- 5
    ('Ofada Spot',              'restaurant',  'Uche Okonkwo',     '+2348091146608', NULL,                       '22 Opebi Road, Ikeja',               'Ikeja');        -- 6

INSERT INTO sales_order (customer_id, taken_by, placed_at, delivery_date, status) VALUES
    (2, 6, '2026-11-04 10:15+01', '2026-11-05', 'delivered'),   -- 1
    (4, 7, '2026-11-04 15:40+01', '2026-11-05', 'delivered'),   -- 2
    (1, 6, '2026-11-05 09:05+01', '2026-11-06', 'delivered'),   -- 3
    (3, 7, '2026-11-06 11:30+01', '2026-11-08', 'delivered'),   -- 4
    (1, 6, '2026-11-07 08:50+01', '2026-11-08', 'cancelled'),   -- 5
    (5, 6, '2026-11-08 12:20+01', '2026-11-10', 'confirmed'),   -- 6
    (6, 7, '2026-11-09 16:45+01', '2026-11-11', 'pending');     -- 7

INSERT INTO order_line VALUES
    (1, 1, 1, 'A',  30, 38000),
    (1, 2, 3, 'A',  10, 55000),
    (1, 3, 8, 'A',   8, 30000),
    (2, 1, 2, 'A',  20, 120000),
    (3, 1, 1, 'B',  15, 32000),
    (3, 2, 4, 'A', 100, 4500),
    (3, 3, 6, 'B',   5, 40000),
    (4, 1, 1, 'A',  35, 38000),   -- priced before the 7 November rise
    (4, 2, 5, 'A',  40, 9000),
    (4, 3, 4, 'B', 120, 3500),
    (5, 1, 1, 'C',  10, 24000),
    (6, 1, 1, 'A',  20, 42000),
    (6, 2, 5, 'B',  30, 7000),
    (6, 3, 7, 'B',  10, 18000),
    (7, 1, 4, 'A', 150, 4500),
    (7, 2, 6, 'A',   4, 45000);

-- Order 5 was cancelled and order 7 is still pending, so neither has stock.
-- Order 4 line 1 had to be split: lot 1 ran out, lot 14 arrived on the 7th.
INSERT INTO allocation VALUES
    (1, 1, 1,  30),
    (1, 2, 5,  10),
    (1, 3, 6,   8),
    (2, 1, 3,  20),
    (3, 1, 2,  15),
    (3, 2, 8, 100),
    (3, 3, 4,   5),
    (4, 1, 1,  30),
    (4, 1, 14,  5),
    (4, 2, 12, 40),
    (4, 3, 9, 120),
    (6, 1, 14, 20),
    (6, 2, 13, 30),
    (6, 3, 7,  10);

UPDATE produce_lot l
SET qty_remaining = l.qty_received - a.allocated
FROM (SELECT lot_id, sum(quantity) AS allocated
      FROM allocation GROUP BY lot_id) a
WHERE a.lot_id = l.lot_id;

-- Order 2 was paid in two parts. Order 4 has paid a deposit only.
INSERT INTO payment (order_id, amount, method, reference, paid_at) VALUES
    (1, 1930000, 'transfer', 'NIP000231104771', '2026-11-05 16:02+01'),
    (2, 1500000, 'transfer', 'NIP000231105392', '2026-11-05 11:48+01'),
    (2,  900000, 'transfer', 'NIP000231107015', '2026-11-07 10:21+01'),
    (3, 1130000, 'pos',      'POS-2201-884213', '2026-11-06 13:35+01'),
    (4, 1055000, 'transfer', 'NIP000231106640', '2026-11-06 11:52+01');

COMMIT;
