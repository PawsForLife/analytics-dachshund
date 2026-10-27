-- Dataset: pr_index_comp
-- Title: Price index by competitor
-- Tab: Price
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Auto Delivery price index for KVI, Core and Tail against each of Petbarn, Petstock, PetO and Budget Pet Products separately at the reporting Sunday, with week-on-week and 12 prior Sunday average moves. Reads product__price_component__eod, product__product_variant__eod, customer__customer_order_basket, product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_end_date AS we FROM cal WHERE is_latest_merch_complete_week = TRUE),
snap AS (
  SELECT DATE_SUB(r.we, INTERVAL 7 * k DAY) AS sd, k FROM r, UNNEST(GENERATE_ARRAY(0, 12)) AS k
),
rng AS (SELECT MIN(sd) AS s0, MAX(sd) AS s1 FROM snap),
pc AS (
  SELECT p.valid_for_date AS sd, p.product_variant_code AS pvc, p.recurring_price AS ours, c.competitor_name AS comp, MIN(c.competitor_price) AS cp
  FROM `petcircle-warehouse-cloud.business_layer.product__price_component__eod` p, UNNEST(p.competitor_price_component) c
  CROSS JOIN rng
  WHERE p.valid_for_date BETWEEN rng.s0 AND rng.s1
    AND p.valid_for_date IN (SELECT sd FROM snap)
    AND c.price_type = 'Auto Delivery Price' AND c.is_latest_price_type_scrape AND c.competitor_price > 0
    AND c.competitor_marketplace = 'No Marketplace'
    AND c.competitor_name IN ('Petbarn', 'Petstock', 'PetO', 'Budget Pet Products')
  GROUP BY 1, 2, 3, 4
),
grp AS (
  SELECT e.valid_for_date AS sd, e.product_variant_code AS pvc, ANY_VALUE(e.multi_track_pricing_group) AS mtp
  FROM `petcircle-warehouse-cloud.business_layer.product__product_variant__eod` e
  CROSS JOIN rng
  WHERE e.valid_for_date BETWEEN rng.s0 AND rng.s1
    AND e.valid_for_date IN (SELECT sd FROM snap)
  GROUP BY 1, 2
),
dl AS (
  SELECT o.order_created_date AS od, b.product_variant_code AS pvc,
    SUM(b.product_variant_revenue_complete_excl_gst) AS rev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au') b
  JOIN (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o ON o.order_id = b.order_id
  CROSS JOIN rng
  WHERE o.status != 'Cancelled'
    AND o.order_created_date BETWEEN DATE_SUB(rng.s0, INTERVAL 83 DAY) AND rng.s1
    AND b.order_created_date BETWEEN DATE_SUB(rng.s0, INTERVAL 90 DAY) AND DATE_ADD(rng.s1, INTERVAL 7 DAY)
  GROUP BY 1, 2
),
w AS (
  SELECT snap.sd, dl.pvc, SUM(dl.rev) AS rev12
  FROM snap JOIN dl ON dl.od BETWEEN DATE_SUB(snap.sd, INTERVAL 83 DAY) AND snap.sd
  GROUP BY 1, 2
),
m AS (
  SELECT snap.k, CASE grp.mtp WHEN 'Longtail' THEN 'Tail' ELSE grp.mtp END AS pricing_group, pc.comp, pc.ours, pc.cp, w.rev12
  FROM snap
  JOIN pc ON pc.sd = snap.sd
  JOIN grp ON grp.sd = pc.sd AND grp.pvc = pc.pvc
  JOIN w ON w.sd = pc.sd AND w.pvc = pc.pvc
  WHERE pc.ours > 0 AND w.rev12 > 0 AND grp.mtp IN ('KVI', 'Core', 'Longtail')
),
agg AS (
  SELECT k, pricing_group, comp, COUNT(*) AS n, SUM(rev12 * ours / cp) / SUM(rev12) AS ix
  FROM m GROUP BY 1, 2, 3
),
cur AS (SELECT * FROM agg WHERE k = 0),
lw AS (SELECT * FROM agg WHERE k = 1),
p12 AS (SELECT pricing_group, comp, AVG(ix) AS a12 FROM agg WHERE k BETWEEN 1 AND 12 GROUP BY 1, 2)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  cur.pricing_group,
  CASE cur.pricing_group WHEN 'KVI' THEN 1 WHEN 'Core' THEN 2 ELSE 3 END AS group_sort,
  cur.comp AS competitor,
  CASE cur.comp WHEN 'Petbarn' THEN 1 WHEN 'Petstock' THEN 2 WHEN 'PetO' THEN 3 ELSE 4 END AS comp_sort,
  cur.n AS matched_skus,
  ROUND(cur.ix, 4) AS ad_index,
  ROUND(cur.ix - lw.ix, 4) AS ad_index_wow,
  ROUND(cur.ix - p12.a12, 4) AS ad_index_vs_avg12
FROM cur CROSS JOIN r
LEFT JOIN lw ON lw.pricing_group = cur.pricing_group AND lw.comp = cur.comp
LEFT JOIN p12 ON p12.pricing_group = cur.pricing_group AND p12.comp = cur.comp
ORDER BY group_sort, comp_sort
