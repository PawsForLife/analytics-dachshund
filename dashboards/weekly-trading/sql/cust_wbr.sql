-- Dataset: cust_wbr
-- Title: Customer WBR tables
-- Tab: Customer
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: The three Marketing WBR comparison tables (new customer shape, customer health, value and behaviour segments) with this week, target, last week, 4 and 12-week averages, LY and the deltas. Reads product__customer_order, customer__customer_order_basket, customer__customer_recency_frequency_monetary_segments__eod, customer__customer_lifecycle_attributes__eod, company__performance_target_by_day, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week
),
wk AS (
  SELECT w.week_start_date AS ws, w.week_end_date AS we, CAST(DATE_DIFF(c.we, w.week_end_date, DAY) / 7 AS INT64) AS k
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` w CROSS JOIN cal c
  WHERE w.week_end_date BETWEEN DATE_SUB(c.we, INTERVAL 84 DAY) AND c.we
  UNION ALL
  SELECT week_start_date, week_end_date, 99 FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_prior_year_latest_merch_complete_week
),
ord AS (
  SELECT o.order_id, o.customer_id, w.k, w.we, o.order_created_date AS d, o.order_type, o.order_origin, o.is_auto_delivery_order AS ad, o.is_first_customer_order_complete AS fst
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled' AND o.order_created_date >= DATE_SUB((SELECT we FROM cal), INTERVAL 400 DAY)
),
bsk AS (
  SELECT order_id, ANY_VALUE(date_of_previous_order) AS prev, ANY_VALUE(date_of_previous_mobile_app_order) AS prev_app, LOGICAL_OR(is_food) AS food
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date >= DATE_SUB((SELECT we FROM cal), INTERVAL 400 DAY)
  GROUP BY 1
),
cw AS (
  SELECT o.k, ANY_VALUE(o.we) AS we, o.customer_id,
    LOGICAL_OR(o.fst) AS is_new,
    LOGICAL_OR(NOT o.fst AND (b.prev IS NULL OR DATE_DIFF(o.d, b.prev, DAY) >= 92)) AS has_react,
    LOGICAL_OR(o.fst AND o.ad) AS first_ad,
    LOGICAL_OR(o.fst AND IFNULL(b.food, FALSE)) AS first_food,
    LOGICAL_OR(o.ad) AS any_ad,
    LOGICAL_OR(IFNULL(b.food, FALSE)) AS any_food,
    LOGICAL_OR(o.order_origin = 'Mobile App') AS any_app,
    LOGICAL_OR(o.order_origin = 'Mobile App' AND b.order_id IS NOT NULL AND b.prev_app IS NULL) AS first_app,
    LOGICAL_OR(o.order_type = 'Transactional') AS t_tr,
    LOGICAL_OR(o.order_type = 'AD Transactional') AS t_adtr,
    LOGICAL_OR(o.order_type = 'AD Reorder') AS t_adro,
    LOGICAL_OR(o.order_type = 'AD Scheduled') AS t_adsc
  FROM ord o LEFT JOIN bsk b USING (order_id)
  GROUP BY o.k, o.customer_id
),
rfm AS (
  SELECT DISTINCT r.valid_for_date AS we, r.customer_id
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_recency_frequency_monetary_segments__eod` WHERE store_id = 'pc-au') r
  WHERE r.valid_for_date IN (SELECT we FROM wk WHERE k < 99)
    AND r.rfm_segment IN ('Super High Value', 'High Value - Rescue', 'Quality', 'Key Opportunity')
),
pet AS (
  SELECT DISTINCT l.valid_for_date AS we, l.customer_id
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_lifecycle_attributes__eod` WHERE store_id = 'pc-au') l
  WHERE l.valid_for_date IN (SELECT we FROM wk)
    AND l.pet_profile_created_date <= l.valid_for_date
),
rfm_ok AS (
  SELECT DISTINCT valid_for_date AS we FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_recency_frequency_monetary_segments__eod` WHERE store_id = 'pc-au')
  WHERE valid_for_date IN (SELECT we FROM wk)
),
wv AS (
  SELECT c.k,
    COUNT(*) AS active,
    COUNTIF(c.is_new) AS new_c,
    COUNTIF(NOT c.is_new AND c.has_react) AS react,
    COUNTIF(c.first_ad) AS first_ad,
    COUNTIF(c.first_food) AS first_food,
    COUNTIF(c.t_tr) AS t_tr, COUNTIF(c.t_adtr) AS t_adtr, COUNTIF(c.t_adro) AS t_adro, COUNTIF(c.t_adsc) AS t_adsc,
    IF(LOGICAL_OR(ok.we IS NOT NULL), COUNTIF(r.customer_id IS NOT NULL), NULL) AS hv,
    COUNTIF(c.any_ad) AS ad_c, COUNTIF(c.any_ad AND c.is_new) AS ad_new,
    COUNTIF(c.any_food) AS food_c, COUNTIF(c.any_food AND c.is_new) AS food_new,
    COUNTIF(c.any_app) AS app_c, COUNTIF(c.any_app AND c.is_new) AS app_new, COUNTIF(c.any_app AND NOT c.is_new AND c.first_app) AS app_first,
    COUNTIF(p.customer_id IS NOT NULL) AS pet_c
  FROM cw c
  LEFT JOIN rfm r ON r.we = c.we AND r.customer_id = c.customer_id
  LEFT JOIN pet p ON p.we = c.we AND p.customer_id = c.customer_id
  LEFT JOIN rfm_ok ok ON ok.we = c.we AND c.k < 99
  GROUP BY c.k
),
tgt AS (
  SELECT SUM(t.daily_target_new_customer_count) AS t_new,
    SUM(t.daily_target_reactivated_customer_count) AS t_react,
    SUM(t.daily_target_purchasing_customer_count) AS t_active,
    AVG(t.daily_target_new_customer_first_order_auto_delivery_rate) AS t_adr
  FROM `petcircle-warehouse-cloud.business_layer.company__performance_target_by_day` t JOIN wk w ON w.k = 0 AND t.calendar_date BETWEEN w.ws AND w.we
),
lng AS (
  SELECT wv.k, x.key, x.num, x.den
  FROM wv, UNNEST([
    STRUCT('new_c' AS key, CAST(wv.new_c AS FLOAT64) AS num, CAST(NULL AS FLOAT64) AS den),
    STRUCT('pct_ad_first', CAST(wv.first_ad AS FLOAT64), CAST(wv.new_c AS FLOAT64)),
    STRUCT('pct_food_first', CAST(wv.first_food AS FLOAT64), CAST(wv.new_c AS FLOAT64)),
    STRUCT('active', CAST(wv.active AS FLOAT64), NULL),
    STRUCT('react', CAST(wv.react AS FLOAT64), NULL),
    STRUCT('existing', CAST(wv.active - wv.new_c - wv.react AS FLOAT64), NULL),
    STRUCT('t_tr', CAST(wv.t_tr AS FLOAT64), NULL),
    STRUCT('t_adtr', CAST(wv.t_adtr AS FLOAT64), NULL),
    STRUCT('t_adro', CAST(wv.t_adro AS FLOAT64), NULL),
    STRUCT('t_adsc', CAST(wv.t_adsc AS FLOAT64), NULL),
    STRUCT('hv', CAST(wv.hv AS FLOAT64), NULL),
    STRUCT('ad_c', CAST(wv.ad_c AS FLOAT64), NULL),
    STRUCT('ad_new', CAST(wv.ad_new AS FLOAT64), NULL),
    STRUCT('ad_ex', CAST(wv.ad_c - wv.ad_new AS FLOAT64), NULL),
    STRUCT('food_c', CAST(wv.food_c AS FLOAT64), NULL),
    STRUCT('food_new', CAST(wv.food_new AS FLOAT64), NULL),
    STRUCT('food_ex', CAST(wv.food_c - wv.food_new AS FLOAT64), NULL),
    STRUCT('app_c', CAST(wv.app_c AS FLOAT64), NULL),
    STRUCT('app_new', CAST(wv.app_new AS FLOAT64), NULL),
    STRUCT('app_first', CAST(wv.app_first AS FLOAT64), NULL),
    STRUCT('app_ex', CAST(wv.app_c - wv.app_new - wv.app_first AS FLOAT64), NULL),
    STRUCT('pet_c', CAST(wv.pet_c AS FLOAT64), NULL)
  ]) x
),
agg AS (
  SELECT key,
    IF(MAX(den) IS NULL, SUM(IF(k = 0, num, NULL)), SAFE_DIVIDE(SUM(IF(k = 0, num, NULL)), SUM(IF(k = 0, den, NULL))) * 100) AS tw,
    IF(MAX(den) IS NULL, NULL, SUM(IF(k = 0, num, NULL))) AS tw_n,
    IF(MAX(den) IS NULL, SUM(IF(k = 1, num, NULL)), SAFE_DIVIDE(SUM(IF(k = 1, num, NULL)), SUM(IF(k = 1, den, NULL))) * 100) AS lw,
    IF(MAX(den) IS NULL, AVG(IF(k BETWEEN 1 AND 4, num, NULL)), SAFE_DIVIDE(SUM(IF(k BETWEEN 1 AND 4, num, NULL)), SUM(IF(k BETWEEN 1 AND 4, den, NULL))) * 100) AS avg4,
    IF(MAX(den) IS NULL, AVG(IF(k BETWEEN 1 AND 12, num, NULL)), SAFE_DIVIDE(SUM(IF(k BETWEEN 1 AND 12, num, NULL)), SUM(IF(k BETWEEN 1 AND 12, den, NULL))) * 100) AS avg12,
    IF(MAX(den) IS NULL, SUM(IF(k = 99, num, NULL)), SAFE_DIVIDE(SUM(IF(k = 99, num, NULL)), SUM(IF(k = 99, den, NULL))) * 100) AS ly
  FROM lng GROUP BY key
),
defs AS (
  SELECT * FROM UNNEST([
    STRUCT('new' AS block, 1 AS sort, 'New customers' AS metric, 'First-ever completed order in the week' AS sub, 'n' AS unit, FALSE AS child, 'warehouse' AS source, 'new_c' AS key, FALSE AS inverted),
    STRUCT('new', 2, 'Acquisition spend', 'Performance media spend from the Marketing Performance Tracker, not held in the warehouse', 'n', FALSE, 'tracker', CAST(NULL AS STRING), FALSE),
    STRUCT('new', 3, 'Payback', 'Months to recover acquisition spend, from the Marketing Performance Tracker', 'n', FALSE, 'tracker', NULL, TRUE),
    STRUCT('new', 4, 'Performance CPA', 'Performance media cost per acquisition, from the Marketing Performance Tracker', 'n', FALSE, 'tracker', NULL, TRUE),
    STRUCT('new', 5, '% AD first order', 'Share of new customers in the week whose first-ever order was an Auto Delivery order', 'pct', FALSE, 'warehouse', 'pct_ad_first', FALSE),
    STRUCT('new', 6, '% Food first order', 'Share of new customers in the week whose first basket held a Food or Chilled line', 'pct', FALSE, 'warehouse', 'pct_food_first', FALSE),
    STRUCT('health', 1, 'Total active customers', 'Distinct customers with at least one order in the week', 'n', FALSE, 'warehouse', 'active', FALSE),
    STRUCT('health', 2, 'New customers', 'First-ever completed order in the week', 'n', FALSE, 'warehouse', 'new_c', FALSE),
    STRUCT('health', 3, 'Reactivations', 'Returned to the active base after a gap of 92 days or more, or no prior order on record', 'n', FALSE, 'warehouse', 'react', FALSE),
    STRUCT('health', 4, 'Active customers - existing', 'Total active customers less new customers less reactivations', 'n', FALSE, 'warehouse', 'existing', FALSE),
    STRUCT('health', 5, 'Transactional', 'One-time purchase outside Auto Delivery. Counts customers with at least one order of this type, so the four rows overlap and do not sum to total active customers', 'n', TRUE, 'warehouse', 't_tr', FALSE),
    STRUCT('health', 6, 'AD Transactional', 'Manually created Auto Delivery order. Counts customers with at least one order of this type, so the four rows overlap and do not sum to total active customers', 'n', TRUE, 'warehouse', 't_adtr', FALSE),
    STRUCT('health', 7, 'AD Reorder', 'Reordered Auto Delivery order. Counts customers with at least one order of this type, so the four rows overlap and do not sum to total active customers', 'n', TRUE, 'warehouse', 't_adro', FALSE),
    STRUCT('health', 8, 'AD Scheduled', 'System-generated Auto Delivery order. Counts customers with at least one order of this type, so the four rows overlap and do not sum to total active customers', 'n', TRUE, 'warehouse', 't_adsc', FALSE),
    STRUCT('features', 1, 'High value customers', 'Purchased in the week and sat in Super High Value, High Value - Rescue, Quality or Key Opportunity on 365-day RFM at week end', 'n', FALSE, 'warehouse', 'hv', FALSE),
    STRUCT('features', 2, 'AD customers', 'Made an Auto Delivery purchase in the week', 'n', FALSE, 'warehouse', 'ad_c', FALSE),
    STRUCT('features', 3, 'AD customers - New to Pet Circle', 'AD purchasers whose first-ever completed order was in this week', 'n', TRUE, 'warehouse', 'ad_new', FALSE),
    STRUCT('features', 4, 'AD customers - Existing', 'AD purchasers who had ordered before this week', 'n', TRUE, 'warehouse', 'ad_ex', FALSE),
    STRUCT('features', 5, 'Food customers', 'Bought a Food or Chilled line in the week', 'n', FALSE, 'warehouse', 'food_c', FALSE),
    STRUCT('features', 6, 'Food customers - New to Pet Circle', 'Food purchasers whose first-ever completed order was in this week', 'n', TRUE, 'warehouse', 'food_new', FALSE),
    STRUCT('features', 7, 'Food customers - Existing', 'Food purchasers who had ordered before this week', 'n', TRUE, 'warehouse', 'food_ex', FALSE),
    STRUCT('features', 8, 'App customers', 'Placed an order on the mobile app in the week', 'n', FALSE, 'warehouse', 'app_c', FALSE),
    STRUCT('features', 9, 'App customers - New to Pet Circle', 'App purchasers whose first-ever completed order was in this week', 'n', TRUE, 'warehouse', 'app_new', FALSE),
    STRUCT('features', 10, 'App customers - New to App', 'App purchasers who had ordered from Pet Circle before, on the website only, and placed their first app order this week', 'n', TRUE, 'warehouse', 'app_first', FALSE),
    STRUCT('features', 11, 'App customers - Existing app customers', 'App purchasers who had already ordered on the app before this week', 'n', TRUE, 'warehouse', 'app_ex', FALSE),
    STRUCT('features', 12, 'Customers with a pet profile', 'Purchased in the week and held at least one pet profile at week end', 'n', FALSE, 'warehouse', 'pet_c', FALSE)
  ])
),
j AS (
  SELECT d.*, a.tw, a.tw_n, a.lw, a.avg4, a.avg12, a.ly,
    CASE d.key
      WHEN 'new_c' THEN t.t_new
      WHEN 'react' THEN t.t_react
      WHEN 'active' THEN t.t_active
      WHEN 'existing' THEN t.t_active - t.t_new - t.t_react
      WHEN 'pct_ad_first' THEN t.t_adr * 100
    END AS target
  FROM defs d LEFT JOIN agg a USING (key) CROSS JOIN tgt t
)
SELECT
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end,
  block, sort, metric, sub, unit, child, source,
  ROUND(tw, 4) AS tw, CAST(tw_n AS INT64) AS tw_n, ROUND(target, 4) AS target, ROUND(lw, 4) AS lw, ROUND(avg4, 4) AS avg4, ROUND(avg12, 4) AS avg12, ROUND(ly, 4) AS ly,
  ROUND(IF(unit = 'pct', tw - target, SAFE_DIVIDE(tw, target) - 1), 4) AS d_target,
  ROUND(IF(unit = 'pct', tw - lw, SAFE_DIVIDE(tw, lw) - 1), 4) AS d_lw,
  ROUND(IF(unit = 'pct', tw - avg4, SAFE_DIVIDE(tw, avg4) - 1), 4) AS d_avg4,
  ROUND(IF(unit = 'pct', tw - avg12, SAFE_DIVIDE(tw, avg12) - 1), 4) AS d_avg12,
  ROUND(IF(unit = 'pct', tw - ly, SAFE_DIVIDE(tw, ly) - 1), 4) AS d_ly,
  inverted
FROM j
ORDER BY CASE block WHEN 'new' THEN 1 WHEN 'health' THEN 2 ELSE 3 END, sort
