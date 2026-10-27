-- Dataset: commercial_explorer
-- Title: Commercial explorer cube
-- Tab: Commercial
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Product revenue, product margin, orders, purchasing customers and AOV for the reporting week against last week, the 12-week average, 445 LY and the category plan, split by book, category, brand, channel, customer status and delivery state. Category and brand keep the eight biggest movers per comparison. Reads product__customer_order, customer__customer_order_basket, logistics__customer_order_delivery, product__targets_category_by_day, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_start_date AS rws, week_end_date AS rwe FROM cal WHERE is_latest_merch_complete_week = TRUE),
wk AS (
  SELECT c.week_start_date AS ws, c.week_end_date AS we,
    c.week_end_date = r.rwe AS is_tw,
    c.week_end_date = DATE_SUB(r.rwe, INTERVAL 7 DAY) AS is_lw,
    c.week_end_date < r.rwe AND NOT c.is_prior_year_latest_merch_complete_week AS is_p12,
    c.is_prior_year_latest_merch_complete_week AS is_ly
  FROM cal c CROSS JOIN r
  WHERE c.week_end_date BETWEEN DATE_SUB(r.rwe, INTERVAL 84 DAY) AND r.rwe
     OR c.is_prior_year_latest_merch_complete_week = TRUE
),
rng AS (SELECT MIN(ws) AS d0, MAX(we) AS d1 FROM wk),
o0 AS (
  SELECT w.we, o.order_id, o.order_created_date AS od,
    ANY_VALUE(o.customer_id) AS customer_id,
    ANY_VALUE(o.order_origin) AS origin,
    ANY_VALUE(o.is_first_customer_order_complete) AS is_new,
    ANY_VALUE(o.product_revenue_complete_excl_gst) AS rev,
    ANY_VALUE(o.product_margin_complete_excl_gst) AS pm
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled'
    AND o.order_created_date BETWEEN (SELECT d0 FROM rng) AND (SELECT d1 FROM rng)
  GROUP BY w.we, o.order_id, o.order_created_date
),
bk AS (
  SELECT order_id, ANY_VALUE(date_of_previous_order) AS prev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date BETWEEN (SELECT d0 FROM rng) AND (SELECT d1 FROM rng)
  GROUP BY order_id
),
st AS (
  SELECT order_id, ANY_VALUE(customer_order_delivery_address.state) AS state
  FROM `petcircle-warehouse-cloud.business_layer.logistics__customer_order_delivery`
  WHERE order_created_date BETWEEN (SELECT d0 FROM rng) AND (SELECT d1 FROM rng)
  GROUP BY order_id
),
o AS (
  SELECT o0.we, o0.order_id, o0.customer_id, IFNULL(o0.rev, 0) AS rev, IFNULL(o0.pm, 0) AS pm,
    CASE WHEN o0.origin = 'Schedule' THEN 'AD Scheduled' ELSE IFNULL(o0.origin, 'Unknown') END AS channel,
    CASE WHEN o0.is_new THEN 'New'
      WHEN bk.prev IS NULL OR DATE_DIFF(o0.od, bk.prev, DAY) >= 92 THEN 'Reactivated'
      ELSE 'Returning' END AS cstatus,
    IFNULL(NULLIF(UPPER(TRIM(st.state)), ''), 'UNKNOWN') AS state
  FROM o0 LEFT JOIN bk USING (order_id) LEFT JOIN st USING (order_id)
),
ln AS (
  SELECT o.we,
    IFNULL(b.category_description, 'Unknown') AS category,
    IFNULL(NULLIF(TRIM(b.brand), ''), 'No brand') AS brand,
    IFNULL(b.product_variant_revenue_complete_excl_gst, 0) AS rev,
    IFNULL(b.product_variant_margin_complete_excl_gst, 0) AS mg
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au') b
  JOIN (SELECT DISTINCT we, order_id FROM o) o ON o.order_id = b.order_id
  WHERE b.order_created_date BETWEEN DATE_SUB((SELECT d0 FROM rng), INTERVAL 7 DAY) AND DATE_ADD((SELECT d1 FROM rng), INTERVAL 7 DAY)
),
lnb AS (
  SELECT ln.*,
    CASE
      WHEN category IN ('Food', 'Treats', 'Chilled', 'Litter', 'Bundle Boxes', 'Better Bundle') THEN 'Core Consumables'
      WHEN category IN ('Flea and Worming', 'Health', 'Grooming', 'Bird', 'Horse', 'Small Animal', 'Fish', 'Reptile') THEN 'Health & Other Species'
      WHEN category IN ('Toys', 'Training and Clean Up', 'Housing and Bedding', 'Smart Pet Products', 'Apparel and Accessories', 'Car and Travel Accessories', 'Feeding and Watering') THEN 'Hardlines'
      ELSE 'Unmapped' END AS book
  FROM ln
),
-- weekly values: one row per metric x split x segment x week (segment 'Total' = the scorecard figure)
wv AS (
  SELECT we, x.metric, x.split, x.segment, x.v FROM (
    SELECT we, 'channel' AS split, channel AS seg, SUM(rev) AS rev, SUM(pm) AS pm, COUNT(DISTINCT order_id) AS ord, COUNT(DISTINCT customer_id) AS cust FROM o GROUP BY 1, 2, 3
    UNION ALL SELECT we, 'status', cstatus, SUM(rev), SUM(pm), COUNT(DISTINCT order_id), COUNT(DISTINCT customer_id) FROM o GROUP BY 1, 2, 3
    UNION ALL SELECT we, 'state', state, SUM(rev), SUM(pm), COUNT(DISTINCT order_id), COUNT(DISTINCT customer_id) FROM o GROUP BY 1, 2, 3
    UNION ALL SELECT we, s, 'Total', SUM(rev), SUM(pm), COUNT(DISTINCT order_id), COUNT(DISTINCT customer_id) FROM o, UNNEST(['channel', 'status', 'state', 'book', 'category', 'brand']) s GROUP BY 1, 2, 3
  ) t,
  UNNEST([
    STRUCT('revenue' AS metric, t.split AS split, t.seg AS segment, t.rev AS v),
    STRUCT('margin', t.split, t.seg, t.pm),
    STRUCT('orders', t.split, t.seg, CAST(t.ord AS FLOAT64)),
    STRUCT('customers', t.split, t.seg, CAST(t.cust AS FLOAT64)),
    STRUCT('aov', t.split, t.seg, SAFE_DIVIDE(t.rev, t.ord))
  ]) x
  WHERE NOT (t.split IN ('book', 'category', 'brand') AND t.seg != 'Total')
    AND NOT (t.split IN ('book', 'category', 'brand') AND x.metric IN ('orders', 'customers', 'aov'))
  UNION ALL
  SELECT we, m, s, seg, v FROM (
    SELECT we, 'book' AS s, book AS seg, SUM(rev) AS rev, SUM(mg) AS mg FROM lnb GROUP BY 1, 2, 3
    UNION ALL SELECT we, 'category', category, SUM(rev), SUM(mg) FROM lnb GROUP BY 1, 2, 3
    UNION ALL SELECT we, 'brand', brand, SUM(rev), SUM(mg) FROM lnb GROUP BY 1, 2, 3
  ), UNNEST([STRUCT('revenue' AS m, rev AS v), STRUCT('margin', mg)])
),
-- per segment: this week and the three comparison bases (L12 = mean of the 12 prior weeks, as the scorecard)
segs AS (
  SELECT metric, split, segment,
    IFNULL(SUM(IF(w.is_tw, v, NULL)), 0) AS cur,
    IFNULL(SUM(IF(w.is_lw, v, NULL)), 0) AS b_lw,
    IF(metric = 'aov', AVG(IF(w.is_p12, v, NULL)), IFNULL(SUM(IF(w.is_p12, v, NULL)), 0) / 12) AS b_l12,
    IFNULL(SUM(IF(w.is_ly, v, NULL)), 0) AS b_ly
  FROM wv JOIN wk w USING (we)
  GROUP BY 1, 2, 3
),
-- plan by merchandise category (finance category targets), revenue and margin only
pl AS (
  SELECT
    CASE REGEXP_REPLACE(ARRAY_REVERSE(SPLIT(t.category_name, ' : '))[OFFSET(0)], r'^[A-Z](\.[A-Z])?\.? ', '')
      WHEN 'Bundle Boxes' THEN 'Better Bundle'
      ELSE REGEXP_REPLACE(ARRAY_REVERSE(SPLIT(t.category_name, ' : '))[OFFSET(0)], r'^[A-Z](\.[A-Z])?\.? ', '') END AS category,
    SUM(t.daily_product_revenue_target) AS rev, SUM(t.daily_product_margin_target) AS mg
  FROM `petcircle-warehouse-cloud.business_layer.product__targets_category_by_day` t
  CROSS JOIN r
  WHERE t.calendar_date BETWEEN r.rws AND r.rwe
  GROUP BY 1
),
plb AS (
  SELECT pl.*,
    CASE
      WHEN category IN ('Food', 'Treats', 'Chilled', 'Litter', 'Bundle Boxes', 'Better Bundle') THEN 'Core Consumables'
      WHEN category IN ('Flea and Worming', 'Health', 'Grooming', 'Bird', 'Horse', 'Small Animal', 'Fish', 'Reptile') THEN 'Health & Other Species'
      WHEN category IN ('Toys', 'Training and Clean Up', 'Housing and Bedding', 'Smart Pet Products', 'Apparel and Accessories', 'Car and Travel Accessories', 'Feeding and Watering') THEN 'Hardlines'
      ELSE 'Unmapped' END AS book
  FROM pl
),
plan_seg AS (
  SELECT m AS metric, s AS split, seg AS segment, SUM(v) AS b_plan FROM (
    SELECT 'book' AS s, book AS seg, rev, mg FROM plb
    UNION ALL SELECT 'category', category, rev, mg FROM plb
  ), UNNEST([STRUCT('revenue' AS m, rev AS v), STRUCT('margin', mg)])
  GROUP BY 1, 2, 3
),
-- long form: one row per metric x split x period x segment
lf AS (
  SELECT metric, split, p.period, segment, cur,
    CASE p.period WHEN 'lw' THEN b_lw WHEN 'l12' THEN b_l12 ELSE b_ly END AS base
  FROM segs, UNNEST([STRUCT('lw' AS period), STRUCT('l12'), STRUCT('ly')]) p
  UNION ALL
  SELECT COALESCE(s.metric, ps.metric), COALESCE(s.split, ps.split), 'plan', COALESCE(s.segment, ps.segment),
    IFNULL(s.cur, 0), IFNULL(ps.b_plan, 0)
  FROM (SELECT * FROM segs WHERE split IN ('book', 'category') AND segment != 'Total') s
  FULL JOIN plan_seg ps ON s.metric = ps.metric AND s.split = ps.split AND s.segment = ps.segment
),
-- category and brand: keep the 8 biggest movers for each metric and period, roll the rest into one bucket
rk AS (
  SELECT lf.*, ROW_NUMBER() OVER (PARTITION BY metric, split, period ORDER BY ABS(cur - IFNULL(base, 0)) DESC, segment) AS rn
  FROM lf WHERE segment != 'Total'
),
seg_rows AS (
  SELECT metric, split, period,
    IF(split IN ('category', 'brand') AND rn > 8, IF(split = 'brand', 'All other brands', 'All other categories'), segment) AS segment,
    SUM(cur) AS cur, SUM(base) AS base,
    COUNT(*) AS n_members
  FROM rk GROUP BY 1, 2, 3, 4
),
tot AS (
  SELECT metric, split, period, cur, base FROM lf WHERE segment = 'Total'
  UNION ALL
  -- plan view: this week is the order-level total (as the scorecard), the plan is the sum of category targets
  SELECT p.metric, p.split, 'plan', t.cur, p.base
  FROM (SELECT metric, split, SUM(base) AS base FROM lf WHERE period = 'plan' GROUP BY 1, 2) p
  JOIN (SELECT metric, split, cur FROM segs WHERE segment = 'Total') t USING (metric, split)
),
-- line-level splits are basket lines; their sum can differ slightly from order-level product revenue
gap AS (
  SELECT t.metric, t.split, t.period, 'Not allocated to a line' AS segment,
    t.cur - s.cur AS cur, t.base - s.base AS base
  FROM tot t JOIN (SELECT metric, split, period, SUM(cur) AS cur, SUM(base) AS base FROM seg_rows GROUP BY 1, 2, 3) s
    USING (metric, split, period)
  WHERE t.split IN ('book', 'category', 'brand')
    AND ABS((t.cur - s.cur) - (t.base - s.base)) >= 0.5
),
allr AS (
  SELECT metric, split, period, segment, cur, base, n_members, FALSE AS is_total FROM seg_rows
  UNION ALL SELECT metric, split, period, segment, cur, base, 1, FALSE FROM gap
  UNION ALL SELECT metric, split, period, 'Total', cur, base, NULL, TRUE FROM tot
)
SELECT
  metric, split, period,
  REGEXP_REPLACE(REGEXP_REPLACE(segment, r'[\x{2013}\x{2014}]', '-'), r'[\x{2018}\x{2019}\x{201C}\x{201D}]', "'") AS segment,
  is_total,
  CASE WHEN is_total THEN 99
    WHEN segment LIKE 'All other%' THEN 97
    WHEN segment = 'Not allocated to a line' THEN 98
    WHEN split = 'state' THEN STRPOS('NSW|VIC|QLD|WA |SA |ACT|TAS|NT |UNK', RPAD(SUBSTR(segment, 1, 3), 3, ' '))
    ELSE 0 END AS sort,
  n_members,
  ROUND(cur, IF(metric IN ('revenue', 'margin', 'aov'), 2, 4)) AS cur,
  ROUND(base, IF(metric IN ('revenue', 'margin', 'aov'), 2, 4)) AS base,
  ROUND(cur - base, IF(metric IN ('revenue', 'margin', 'aov'), 2, 4)) AS delta,
  ROUND(SAFE_DIVIDE(cur, NULLIF(base, 0)) - 1, 4) AS pct,
  IF(is_total, NULL, ROUND(SAFE_DIVIDE(cur - base, NULLIF(MAX(IF(is_total, cur - base, NULL)) OVER (PARTITION BY metric, split, period), 0)), 4)) AS share,
  (SELECT FORMAT_DATE('%F', rwe) FROM r) AS week_end
FROM allr
WHERE NOT (metric = 'aov' AND segment LIKE 'All other%')
ORDER BY metric, split, period, is_total, ABS(cur - base) DESC
