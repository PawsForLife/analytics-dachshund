-- Dataset: cust_overview
-- Title: Customer overview
-- Tab: Customer
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: One-row funnel from the customer file to this week's purchasers, their Food / AD / super-user mix and the A92 base movement. Reads product__customer_order, customer__customer_order_basket, customer__customer_lifecycle_attributes__eod, customer__customer_recency_frequency_monetary_segments__eod, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT week_start_date AS ws, week_end_date AS we, DATE_SUB(week_start_date, INTERVAL 1 DAY) AS ps FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week
),
ord AS (
  SELECT o.order_id, o.customer_id, o.order_origin AS origin, o.is_auto_delivery_order AS ad, o.is_first_customer_order_complete AS fst, o.product_revenue_complete_excl_gst AS rev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  WHERE o.status != 'Cancelled' AND o.order_created_date BETWEEN (SELECT ws FROM cal) AND (SELECT we FROM cal)
),
bk AS (
  SELECT order_id, LOGICAL_OR(is_food) AS food
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date BETWEEN (SELECT ws FROM cal) AND (SELECT we FROM cal)
  GROUP BY 1
),
cw AS (
  SELECT o.customer_id, LOGICAL_OR(IFNULL(b.food, FALSE)) AS f, LOGICAL_OR(o.ad) AS a, LOGICAL_OR(o.origin = 'Mobile App') AS p, LOGICAL_OR(o.fst) AS n, SUM(o.rev) AS rev
  FROM ord o LEFT JOIN bk b USING (order_id) GROUP BY 1
),
pc AS (
  SELECT COUNT(*) AS purchased, SUM(rev) AS rev, COUNTIF(f) AS fc, COUNTIF(a) AS ac, COUNTIF(f AND a AND p) AS su, SUM(IF(f AND a AND p, rev, 0)) AS su_rev, COUNTIF(n) AS new_c
  FROM cw
),
snap AS (
  SELECT DISTINCT valid_for_date AS s, customer_id
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_lifecycle_attributes__eod` WHERE store_id = 'pc-au')
  WHERE valid_for_date IN ((SELECT we FROM cal), (SELECT ps FROM cal)) AND is_active_92
),
mem AS (
  SELECT customer_id, LOGICAL_OR(s = (SELECT we FROM cal)) AS t, LOGICAL_OR(s = (SELECT ps FROM cal)) AS p FROM snap GROUP BY 1
),
fl AS (
  SELECT COUNTIF(m.p) AS opening, COUNTIF(m.t) AS closing,
    COUNTIF(m.t AND NOT m.p AND IFNULL(c.n, FALSE)) AS flow_new,
    COUNTIF(m.t AND NOT m.p AND NOT IFNULL(c.n, FALSE)) AS reactivated,
    COUNTIF(m.p AND NOT m.t) AS lapsed
  FROM mem m LEFT JOIN cw c USING (customer_id)
),
rf AS (
  SELECT COUNT(DISTINCT customer_id) AS rfm_file
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_recency_frequency_monetary_segments__eod` WHERE store_id = 'pc-au')
  WHERE valid_for_date = (SELECT ps FROM cal)
)
SELECT FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end,
  rf.rfm_file, fl.closing AS a92_base, fl.opening AS a92_opening,
  pc.purchased, ROUND(pc.rev / pc.purchased, 2) AS rev_per_customer,
  ROUND(100 * pc.fc / pc.purchased, 4) AS food_buyer_share,
  ROUND(100 * pc.ac / pc.purchased, 4) AS ad_customer_share,
  pc.su AS super_users, ROUND(100 * pc.su / pc.purchased, 4) AS super_user_share, ROUND(100 * pc.su_rev / pc.rev, 4) AS super_user_rev_share,
  pc.new_c AS new_customers, fl.reactivated, fl.lapsed, fl.closing - fl.opening AS net_change,
  ROUND(100 * pc.purchased / fl.closing, 4) AS purchase_rate
FROM pc CROSS JOIN fl CROSS JOIN rf
