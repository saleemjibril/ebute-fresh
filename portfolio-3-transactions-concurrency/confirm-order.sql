-- confirm_order: reserve stock for a pending order.
--
-- This is the "place an order and reserve stock without overselling"
-- operation from the case study. For each line it takes stock from the
-- oldest lots of the right commodity and grade first, records an
-- allocation, and reduces qty_remaining. If any line cannot be filled the
-- function raises an error, and because it runs inside the caller's
-- transaction, everything it did is rolled back with it.
--
-- Concurrency control:
-- * The order row is locked first, so the same order cannot be confirmed
--   twice at once.
-- * Lots are read with FOR UPDATE. A second sales officer wanting the same
--   lot waits until the first commits, then sees the reduced quantity.
-- * Lines are handled in commodity and grade order, not line order, so two
--   orders being confirmed together always lock lots in the same order and
--   cannot deadlock each other (see 07-deadlock).

CREATE OR REPLACE FUNCTION confirm_order(p_order_id bigint) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
    v_line   record;
    v_lot    record;
    v_needed integer;
    v_take   integer;
BEGIN
    SELECT status INTO v_status
    FROM sales_order
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'order % does not exist', p_order_id;
    END IF;
    IF v_status <> 'pending' THEN
        RAISE EXCEPTION 'order % is already %', p_order_id, v_status;
    END IF;

    FOR v_line IN
        SELECT line_no, commodity_id, grade, quantity
        FROM order_line
        WHERE order_id = p_order_id
        ORDER BY commodity_id, grade
    LOOP
        v_needed := v_line.quantity;

        FOR v_lot IN
            SELECT lot_id, qty_remaining
            FROM produce_lot
            WHERE commodity_id = v_line.commodity_id
              AND grade = v_line.grade
              AND qty_remaining > 0
            ORDER BY received_at, lot_id
            FOR UPDATE
        LOOP
            v_take := least(v_needed, v_lot.qty_remaining);

            INSERT INTO allocation (order_id, line_no, lot_id, quantity)
            VALUES (p_order_id, v_line.line_no, v_lot.lot_id, v_take);

            UPDATE produce_lot
            SET qty_remaining = qty_remaining - v_take
            WHERE lot_id = v_lot.lot_id;

            v_needed := v_needed - v_take;
            EXIT WHEN v_needed = 0;
        END LOOP;

        IF v_needed > 0 THEN
            RAISE EXCEPTION 'not enough stock for order % line %: short by % units',
                            p_order_id, v_line.line_no, v_needed;
        END IF;
    END LOOP;

    UPDATE sales_order SET status = 'confirmed' WHERE order_id = p_order_id;
END;
$$;
