-- Dataset: pr_price_match
-- Title: Price-match summary
-- Tab: Price
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Reporting-week price-match discount, orders and lines using it, change on last week and the 12-week average, and the most-matched competitor. Reads product__customer_order (nested customer_order_basket_discounts), reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_start_date AS ws, week_end_date AS we FROM cal WHERE is_latest_merch_complete_week = TRUE),
wk AS (
  SELECT c.week_start_date AS ws, c.week_end_date AS we,
    DIV(DATE_DIFF(r.we, c.week_end_date, DAY), 7) AS k
  FROM cal c CROSS JOIN r
  WHERE c.week_end_date BETWEEN DATE_SUB(r.we, INTERVAL 84 DAY) AND r.we
),
o AS (
  SELECT wk.k, o.order_id, o.customer_order_basket AS cb
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk ON o.order_created_date BETWEEN wk.ws AND wk.we
  WHERE o.status != 'Cancelled'
    AND o.order_created_date BETWEEN (SELECT MIN(ws) FROM wk) AND (SELECT MAX(we) FROM wk)
),
d AS (
  SELECT o.k, o.order_id, x.price_match_competitor_name AS comp, x.discount_amount_complete_excl_gst AS amt
  FROM o, UNNEST(o.cb) b, UNNEST(b.customer_order_basket_discounts) x
  WHERE x.discount_subtype = 'price-match' AND x.discount_categorisation != 'Coupon'
),
wkagg AS (
  SELECT wk.k, IFNULL(a.orders_pm, 0) AS orders_pm, IFNULL(a.disc, 0) AS disc, IFNULL(a.lines_pm, 0) AS lines_pm, n.orders
  FROM wk
  LEFT JOIN (SELECT k, COUNT(DISTINCT order_id) AS orders_pm, SUM(amt) AS disc, COUNT(*) AS lines_pm FROM d GROUP BY 1) a ON a.k = wk.k
  LEFT JOIN (SELECT k, COUNT(DISTINCT order_id) AS orders FROM o GROUP BY 1) n ON n.k = wk.k
),
cmp AS (
  SELECT IFNULL(comp, 'Not recorded') AS comp, SUM(amt) AS disc, COUNT(DISTINCT order_id) AS orders_c
  FROM d WHERE k = 0 GROUP BY 1
),
topc AS (
  SELECT comp, disc, orders_c FROM cmp WHERE comp != 'Not recorded' ORDER BY disc DESC, comp LIMIT 1
),
cov AS (SELECT SAFE_DIVIDE(SUM(IF(comp != 'Not recorded', disc, 0)), SUM(disc)) AS share_named, COUNT(DISTINCT IF(comp != 'Not recorded', comp, NULL)) AS n_comp FROM cmp),
tw AS (SELECT * FROM wkagg WHERE k = 0),
lw AS (SELECT * FROM wkagg WHERE k = 1),
l12 AS (SELECT AVG(disc) AS disc, AVG(orders_pm) AS orders_pm, COUNT(*) AS n FROM wkagg WHERE k BETWEEN 1 AND 12)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  tw.orders_pm AS orders_with_price_match,
  tw.lines_pm AS price_match_lines,
  ROUND(tw.disc, 2) AS price_match_discount,
  tw.orders AS total_orders,
  ROUND(SAFE_DIVIDE(tw.orders_pm, tw.orders) * 100, 4) AS share_of_orders,
  ROUND(SAFE_DIVIDE(tw.disc, tw.orders_pm), 2) AS avg_match_per_order,
  ROUND(lw.disc, 2) AS price_match_discount_lw,
  lw.orders_pm AS orders_with_price_match_lw,
  ROUND(SAFE_DIVIDE(tw.disc, lw.disc) - 1, 4) AS vs_lw_pct,
  ROUND(l12.disc, 2) AS price_match_discount_l12w_avg,
  ROUND(l12.orders_pm, 1) AS orders_with_price_match_l12w_avg,
  l12.n AS l12w_weeks_used,
  ROUND(SAFE_DIVIDE(tw.disc, l12.disc) - 1, 4) AS vs_l12w_pct,
  REGEXP_REPLACE(topc.comp, r'[^\x20-\x26\x28-\x7E]', '') AS top_competitor,
  ROUND(topc.disc, 2) AS top_competitor_discount,
  topc.orders_c AS top_competitor_orders,
  ROUND(SAFE_DIVIDE(topc.disc, tw.disc) * 100, 4) AS top_competitor_share,
  cov.n_comp AS competitors_matched,
  ROUND(cov.share_named * 100, 4) AS competitor_recorded_share
FROM tw CROSS JOIN lw CROSS JOIN l12 CROSS JOIN cov CROSS JOIN r
LEFT JOIN topc ON TRUE
