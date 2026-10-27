-- Dataset: pr_irritants
-- Title: KVI lines above market
-- Tab: Price
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: KVI SKUs whose AD price is above the cheapest market AD price at the reporting Sunday, ranked by consecutive weeks out of policy then last-week revenue, with whole-list summary columns. Reads product__price_component__eod, product__product_variant__eod, product__product_variant, customer__customer_order_basket, product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_end_date AS we FROM cal WHERE is_latest_merch_complete_week = TRUE),
snap AS (
  SELECT DATE_SUB(r.we, INTERVAL 7 * k DAY) AS sd, k FROM r, UNNEST(GENERATE_ARRAY(0, 25)) AS k
),
rng AS (SELECT MIN(sd) AS s0, MAX(sd) AS s1 FROM snap),
kvi AS (
  SELECT e.product_variant_code AS pvc
  FROM `petcircle-warehouse-cloud.business_layer.product__product_variant__eod` e
  CROSS JOIN r
  WHERE e.valid_for_date = r.we
  GROUP BY 1
  HAVING LOGICAL_OR(e.multi_track_pricing_group = 'KVI')
),
pc AS (
  SELECT p.valid_for_date AS sd, p.product_variant_code AS pvc, p.recurring_price AS ours,
    (SELECT AS STRUCT MIN(c.competitor_price) AS mkt,
        ARRAY_AGG(c.competitor_name ORDER BY c.competitor_price, c.competitor_name LIMIT 1)[OFFSET(0)] AS who
      FROM UNNEST(p.competitor_price_component) c
      WHERE c.price_type = 'Auto Delivery Price' AND c.is_latest_price_type_scrape AND c.competitor_price > 0
        AND c.competitor_marketplace = 'No Marketplace'
        AND c.competitor_name IN ('Petbarn', 'Petstock', 'PetO', 'Budget Pet Products')) AS mk
  FROM `petcircle-warehouse-cloud.business_layer.product__price_component__eod` p
  CROSS JOIN rng
  WHERE p.valid_for_date BETWEEN rng.s0 AND rng.s1
    AND p.valid_for_date IN (SELECT sd FROM snap)
    AND p.product_variant_code IN (SELECT pvc FROM kvi)
),
hist AS (
  SELECT snap.k, kvi.pvc, pc.ours, pc.mk.mkt AS mkt, pc.mk.who AS who,
    IFNULL(pc.ours > 0 AND pc.mk.mkt > 0 AND pc.ours > pc.mk.mkt, FALSE) AS above,
    IFNULL(pc.ours > 0 AND pc.mk.mkt > 0 AND pc.ours <= pc.mk.mkt, FALSE) AS in_policy
  FROM snap CROSS JOIN kvi
  LEFT JOIN pc ON pc.sd = snap.sd AND pc.pvc = kvi.pvc
),
streak AS (
  SELECT pvc, IFNULL(MIN(IF(in_policy, k, NULL)), 26) AS weeks_out,
    MIN(IF(in_policy, k, NULL)) IS NULL AS capped
  FROM hist GROUP BY 1
),
w AS (
  SELECT b.product_variant_code AS pvc,
    SUM(b.product_variant_revenue_complete_excl_gst) AS rev12,
    SUM(IF(o.order_created_date > DATE_SUB(r.we, INTERVAL 7 DAY), b.product_variant_revenue_complete_excl_gst, 0)) AS rev_lw
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au') b
  JOIN (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o ON o.order_id = b.order_id
  CROSS JOIN r
  WHERE o.status != 'Cancelled'
    AND o.order_created_date BETWEEN DATE_SUB(r.we, INTERVAL 83 DAY) AND r.we
    AND b.order_created_date BETWEEN DATE_SUB(r.we, INTERVAL 90 DAY) AND DATE_ADD(r.we, INTERVAL 7 DAY)
    AND b.product_variant_code IN (SELECT pvc FROM kvi)
  GROUP BY 1
),
pv AS (
  SELECT product_variant_code AS pvc, ANY_VALUE(product_variant_display_name) AS sku_name,
    ANY_VALUE(brand) AS brand, ANY_VALUE(category_description) AS sub_category
  FROM `petcircle-warehouse-cloud.business_layer.product__product_variant`
  GROUP BY 1
),
cur AS (
  SELECT h.pvc, pv.sku_name, pv.brand, pv.sub_category,
    CASE
      WHEN pv.sub_category IN ('Food', 'Treats', 'Chilled', 'Litter', 'Bundle Boxes', 'Better Bundle') THEN 'Core Consumables'
      WHEN pv.sub_category IN ('Flea and Worming', 'Health', 'Grooming', 'Bird', 'Horse', 'Small Animal', 'Fish', 'Reptile') THEN 'Health & Other Species'
      WHEN pv.sub_category IN ('Toys', 'Training and Clean Up', 'Housing and Bedding', 'Smart Pet Products', 'Apparel and Accessories', 'Car and Travel Accessories', 'Feeding and Watering') THEN 'Hardlines'
      ELSE 'Unmapped' END AS book,
    h.ours, h.mkt, h.who, IFNULL(w.rev_lw, 0) AS rev_lw, s.weeks_out, s.capped
  FROM hist h
  JOIN streak s ON s.pvc = h.pvc
  JOIN w ON w.pvc = h.pvc
  LEFT JOIN pv ON pv.pvc = h.pvc
  WHERE h.k = 0 AND h.above AND w.rev12 > 0
),
summ AS (
  SELECT COUNT(*) AS n_lines, SUM(rev_lw) AS revenue_total, COUNTIF(weeks_out >= 12) AS n_12w_plus FROM cur
),
ranked AS (
  SELECT cur.*, ROW_NUMBER() OVER (ORDER BY weeks_out DESC, rev_lw DESC, sku_name) AS sort FROM cur
)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  ranked.sort,
  ranked.pvc AS product_variant_code,
  REGEXP_REPLACE(ranked.sku_name, r'[^\x20-\x26\x28-\x7E]', '') AS sku_name,
  REGEXP_REPLACE(ranked.brand, r'[^\x20-\x26\x28-\x7E]', '') AS brand,
  ranked.book,
  ranked.sub_category,
  ROUND(ranked.ours, 2) AS our_ad_price,
  ROUND(ranked.mkt, 2) AS cheapest_price,
  CASE ranked.who WHEN 'Budget Pet Products' THEN 'Budget Pet' ELSE ranked.who END AS cheapest_competitor,
  ROUND((ranked.ours / ranked.mkt - 1) * 100, 2) AS gap_pct,
  ROUND(ranked.rev_lw, 2) AS revenue_lw,
  ranked.weeks_out,
  ranked.capped AS weeks_out_capped,
  summ.n_lines,
  ROUND(summ.revenue_total, 2) AS revenue_total,
  summ.n_12w_plus,
  26 AS streak_lookback_weeks,
  FORMAT_DATE('%F', r.we) AS snapshot_date
FROM ranked CROSS JOIN summ CROSS JOIN r
WHERE ranked.sort <= 30
ORDER BY ranked.sort
