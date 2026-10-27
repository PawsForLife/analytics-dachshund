-- Dataset: inv_books
-- Title: Stock, SLOB and OOS by book
-- Tab: Inventory
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Per merchandise book: stock at cost and SLOB (active vs exit), stock vs last week and LY, OOS lost sales and its share of the book's sales vs last week and the prior 13 weeks, poor-fill and 90-day fill. Reads inventory__item_trading_report, inventory__inventory_holding_status__eod, inventory__customer_order__item_warehouse, inventory__inventory_requisition_order, reference__calendar_4_4_5_week.

WITH cw AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
), lyw AS (
  SELECT week_end_date AS lwe FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_prior_year_latest_merch_complete_week = TRUE
), itr AS (
  SELECT item_code, warehouse_name, category_description AS c, lifecycle_stage AS ls,
    GREATEST(end_of_week_net_stock_quantity, 0) AS q,
    GREATEST(end_of_week_net_stock_quantity, 0) * cost_forecast AS sv,
    last_six_week_average_weekly_items_sold AS u6
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.inventory__item_trading_report`
  WHERE valid_for_date = (SELECT DATE_ADD(we, INTERVAL 1 DAY) FROM cw)
), bk AS (
  SELECT item_code, ANY_VALUE(CASE
    WHEN c IN ('Food', 'Treats', 'Chilled', 'Litter', 'Better Bundle') THEN 'Core Consumables'
    WHEN c IN ('Flea and Worming', 'Health', 'Grooming', 'Bird', 'Horse', 'Small Animal', 'Fish', 'Reptile') THEN 'Health & Other Species'
    WHEN c IN ('Toys', 'Training and Clean Up', 'Housing and Bedding', 'Smart Pet Products', 'Apparel and Accessories', 'Car and Travel Accessories', 'Feeding and Watering') THEN 'Hardlines'
    ELSE 'Unmapped' END) AS book
  FROM itr GROUP BY item_code
), cur AS (
  SELECT COALESCE(b.book, 'Total') AS book,
    SUM(i.sv) AS stk,
    SUM(IF(i.q > 0 AND (IFNULL(i.u6, 0) <= 0 OR i.q / (i.u6 / 7) > 285), i.sv, 0)) AS slob,
    SUM(IF(i.q > 0 AND (IFNULL(i.u6, 0) <= 0 OR i.q / (i.u6 / 7) > 285) AND IFNULL(i.ls, '') NOT IN ('Discontinued', 'Phasing Out', 'Write Off'), i.sv, 0)) AS active_slob,
    SUM(IF(i.q > 0 AND (IFNULL(i.u6, 0) <= 0 OR i.q / (i.u6 / 7) > 285) AND i.ls IN ('Discontinued', 'Phasing Out', 'Write Off'), i.sv, 0)) AS exit_slob
  FROM itr i JOIN bk b USING (item_code)
  GROUP BY ROLLUP(b.book)
), hs AS (
  SELECT COALESCE(x.book, 'Total') AS book,
    SUM(IF(x.d = (SELECT DATE_SUB(we, INTERVAL 7 DAY) FROM cw), x.sv, 0)) AS stk_lw,
    SUM(IF(x.d = (SELECT lwe FROM lyw), x.sv, 0)) AS stk_ly
  FROM (
    SELECT h.valid_for_date AS d, COALESCE(b.book, 'Unmapped') AS book, h.stock_value_cost_forecast AS sv
    FROM `petcircle-warehouse-cloud.business_layer.inventory__inventory_holding_status__eod` h
    LEFT JOIN bk b USING (item_code)
    WHERE h.valid_for_date IN ((SELECT DATE_SUB(we, INTERVAL 7 DAY) FROM cw), (SELECT lwe FROM lyw))
  ) x
  GROUP BY ROLLUP(x.book)
), wk AS (
  SELECT k, DATE_SUB(we, INTERVAL 7 * k DAY) AS d FROM cw, UNNEST(GENERATE_ARRAY(0, 13)) AS k
), oh AS (
  SELECT valid_for_date AS d, item_code, warehouse_name
  FROM `petcircle-warehouse-cloud.business_layer.inventory__inventory_holding_status__eod`
  WHERE valid_for_date IN (SELECT d FROM wk) AND count_item_out_of_stock > 0
), sl AS (
  SELECT wk.k, wk.d, c.item_code, c.warehouse_name, SUM(c.item_revenue) / 6 AS r6
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.inventory__customer_order__item_warehouse` c
  JOIN wk ON c.calendar_date BETWEEN DATE_SUB(wk.d, INTERVAL 41 DAY) AND wk.d
  WHERE c.calendar_date BETWEEN (SELECT DATE_SUB(we, INTERVAL 132 DAY) FROM cw) AND (SELECT we FROM cw)
  GROUP BY 1, 2, 3, 4
), fl AS (
  SELECT d.item_code, d.warehouse_name, SUM(LEAST(d.quantity_received, d.quantity_ordered)) AS rq, SUM(d.quantity_ordered) AS oq
  FROM `petcircle-warehouse-cloud.business_layer.inventory__inventory_requisition_order` o, UNNEST(o.inventory_requisition_order_detail) d
  WHERE o.inventory_requisition_order_stage <> 'Open'
    AND o.inventory_requisition_expected_delivered_date BETWEEN (SELECT DATE_SUB(we, INTERVAL 89 DAY) FROM cw) AND (SELECT we FROM cw)
  GROUP BY 1, 2
), ol AS (
  SELECT sl.k, COALESCE(b.book, 'Unmapped') AS book, sl.r6, oh.item_code IS NOT NULL AS is_oos,
    IFNULL(SAFE_DIVIDE(fl.rq, fl.oq) < 0.92, FALSE) AS poor_fill
  FROM sl
  LEFT JOIN oh USING (d, item_code, warehouse_name)
  LEFT JOIN bk b USING (item_code)
  LEFT JOIN fl USING (item_code, warehouse_name)
), oa AS (
  SELECT COALESCE(ol.book, 'Total') AS bkk, ol.k, SUM(IF(ol.is_oos, ol.r6, 0)) AS lost, SUM(IF(ol.is_oos AND ol.poor_fill, ol.r6, 0)) AS pf, SUM(ol.r6) AS sales
  FROM ol GROUP BY ROLLUP(ol.k, ol.book)
), op AS (
  SELECT bkk AS book,
    MAX(IF(k = 0, lost, NULL)) AS lost0, MAX(IF(k = 0, pf, NULL)) AS pf0, MAX(IF(k = 0, sales, NULL)) AS sales0,
    MAX(IF(k = 0, SAFE_DIVIDE(lost, sales), NULL)) AS pct0,
    MAX(IF(k = 1, SAFE_DIVIDE(lost, sales), NULL)) AS pct1,
    AVG(IF(k BETWEEN 1 AND 13, SAFE_DIVIDE(lost, sales), NULL)) AS pct_l13
  FROM oa WHERE k IS NOT NULL GROUP BY bkk
), fb AS (
  SELECT COALESCE(b.book, 'Unmapped') AS bb, fl.rq, fl.oq
  FROM fl LEFT JOIN bk b USING (item_code)
), fa AS (
  SELECT COALESCE(bb, 'Total') AS book, SAFE_DIVIDE(SUM(rq), SUM(oq)) AS fill
  FROM fb GROUP BY ROLLUP(bb)
)
SELECT
  cur.book,
  CASE cur.book WHEN 'Core Consumables' THEN 1 WHEN 'Health & Other Species' THEN 2 WHEN 'Hardlines' THEN 3 WHEN 'Unmapped' THEN 4 ELSE 9 END AS sort,
  ROUND(cur.stk, 2) AS stock_at_cost,
  ROUND(cur.slob, 2) AS slob,
  ROUND(SAFE_DIVIDE(cur.slob, cur.stk), 4) AS slob_pct,
  ROUND(cur.active_slob, 2) AS active_slob,
  ROUND(cur.exit_slob, 2) AS exit_slob,
  ROUND(hs.stk_lw, 2) AS stock_lw,
  ROUND(hs.stk_ly, 2) AS stock_ly,
  ROUND(SAFE_DIVIDE(cur.stk, hs.stk_lw) - 1, 4) AS stock_vs_lw_pct,
  ROUND(SAFE_DIVIDE(cur.stk, hs.stk_ly) - 1, 4) AS stock_vs_ly_pct,
  ROUND(op.lost0, 2) AS oos_lost_wk,
  ROUND(op.sales0, 2) AS sales_wk_6wk_avg,
  ROUND(op.pct0, 6) AS oos_rev_pct,
  ROUND(op.pct1, 6) AS oos_rev_pct_lw,
  ROUND(100 * (op.pct0 - op.pct1), 4) AS oos_rev_pct_wow_pp,
  ROUND(op.pct_l13, 6) AS oos_rev_pct_l13w,
  ROUND(op.pf0, 2) AS poor_fill_lost,
  ROUND(SAFE_DIVIDE(op.pf0, op.lost0), 4) AS poor_fill_pct,
  ROUND(fa.fill, 4) AS fill_90d,
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw)) AS week_end
FROM cur
LEFT JOIN hs USING (book)
LEFT JOIN op USING (book)
LEFT JOIN fa USING (book)
ORDER BY sort
