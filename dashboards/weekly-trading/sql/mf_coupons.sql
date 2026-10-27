-- Dataset: mf_coupons
-- Title: Coupon orders and cost
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Orders carrying a coupon in the reporting week, with revenue, coupon cost, margin after the coupon and new-customer orders against last week and the prior-12-week average. Reads product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH r AS (
  SELECT week_start_date AS ws, week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
o AS (
  SELECT
    CAST(DIV(DATE_DIFF(r.ws, DATE_TRUNC(o.order_created_date, WEEK(MONDAY)), DAY), 7) AS INT64) AS k,
    IFNULL(o.order_coupon_amount_complete_excl_gst, 0) > 0 AS is_cpn,
    IFNULL(o.order_coupon_amount_complete_excl_gst, 0) AS cpn,
    IFNULL(o.product_revenue_complete_excl_gst, 0) AS rev,
    IFNULL(o.product_margin_complete_excl_gst, 0) AS pm,
    IFNULL(o.is_first_customer_order_complete, FALSE) AS is_new
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o CROSS JOIN r
  WHERE o.status != 'Cancelled'
    AND o.order_created_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.we
),
w AS (
  SELECT k,
    COUNT(*) AS all_orders,
    COUNTIF(is_cpn) AS orders,
    SUM(IF(is_cpn, rev, 0)) AS rev,
    SUM(IF(is_cpn, pm, 0)) AS pm,
    SUM(cpn) AS cpn,
    COUNTIF(is_cpn AND is_new) AS new_orders
  FROM o GROUP BY 1
),
t AS (SELECT * FROM w WHERE k = 0),
lw AS (SELECT * FROM w WHERE k = 1),
b AS (
  SELECT COUNT(*) AS n, AVG(orders) AS orders, AVG(cpn) AS cpn, AVG(rev) AS rev,
    SAFE_DIVIDE(SUM(cpn), SUM(rev)) AS cpn_rate, SAFE_DIVIDE(SUM(pm) - SUM(cpn), SUM(rev)) AS pm_after
  FROM w WHERE k BETWEEN 1 AND 12
)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  'All coupon orders' AS coupon,
  1 AS sort,
  t.orders,
  t.all_orders,
  ROUND(100 * SAFE_DIVIDE(t.orders, t.all_orders), 4) AS orders_share,
  ROUND(t.rev, 2) AS revenue,
  ROUND(t.cpn, 2) AS discount,
  ROUND(100 * SAFE_DIVIDE(t.cpn, t.rev), 4) AS discount_pct_of_rev,
  ROUND(100 * SAFE_DIVIDE(t.pm, t.rev), 4) AS pm_pct_before,
  ROUND(100 * SAFE_DIVIDE(t.pm - t.cpn, t.rev), 4) AS pm_pct_after,
  ROUND(100 * b.pm_after, 4) AS pm_pct_after_l12w,
  ROUND(100 * (SAFE_DIVIDE(t.pm - t.cpn, t.rev) - b.pm_after), 4) AS pm_pct_after_vs_l12w_pp,
  lw.orders AS orders_lw,
  ROUND(SAFE_DIVIDE(t.orders, lw.orders) - 1, 4) AS orders_vs_lw_pct,
  ROUND(b.orders, 1) AS orders_l12w,
  ROUND(SAFE_DIVIDE(t.orders, b.orders) - 1, 4) AS orders_vs_l12w_pct,
  ROUND(lw.cpn, 2) AS discount_lw,
  ROUND(SAFE_DIVIDE(t.cpn, lw.cpn) - 1, 4) AS discount_vs_lw_pct,
  ROUND(b.cpn, 2) AS discount_l12w,
  ROUND(SAFE_DIVIDE(t.cpn, b.cpn) - 1, 4) AS discount_vs_l12w_pct,
  ROUND(100 * (SAFE_DIVIDE(t.cpn, t.rev) - b.cpn_rate), 4) AS discount_pct_of_rev_vs_l12w_pp,
  t.new_orders AS new_customer_orders,
  ROUND(100 * SAFE_DIVIDE(t.new_orders, t.orders), 4) AS new_customer_share,
  b.n AS l12w_weeks,
  FALSE AS code_level_available
FROM t CROSS JOIN lw CROSS JOIN b CROSS JOIN r
