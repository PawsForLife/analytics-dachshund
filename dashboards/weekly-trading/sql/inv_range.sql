-- Dataset: inv_range
-- Title: SKU / variant productivity
-- Tab: Inventory
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Visible variants at the reporting Sunday, how many sold in the last 30 days (productive) and how many did not, vs the LY 445 Sunday, with revenue per productive variant. Reads product__product_variant__eod, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cw AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
), lyw AS (
  SELECT week_end_date AS lwe FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_prior_year_latest_merch_complete_week = TRUE
), v AS (
  SELECT IF(valid_for_date = (SELECT we FROM cw), 'tw', 'ly') AS p, product_variant_code
  FROM `petcircle-warehouse-cloud.business_layer.product__product_variant__eod`
  WHERE valid_for_date IN ((SELECT we FROM cw), (SELECT lwe FROM lyw)) AND is_visible_on_website
), s AS (
  SELECT IF(order_created_date > (SELECT DATE_SUB(we, INTERVAL 30 DAY) FROM cw), 'tw', 'ly') AS p, product_variant_code,
    SUM(product_variant_revenue_complete_excl_gst) AS rev, SUM(quantity_complete) AS qty
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date BETWEEN (SELECT DATE_SUB(we, INTERVAL 29 DAY) FROM cw) AND (SELECT we FROM cw)
     OR order_created_date BETWEEN (SELECT DATE_SUB(lwe, INTERVAL 29 DAY) FROM lyw) AND (SELECT lwe FROM lyw)
  GROUP BY 1, 2
), a AS (
  SELECT p, COUNT(*) AS visible, COUNTIF(IFNULL(s.qty, 0) > 0) AS productive
  FROM v LEFT JOIN s USING (p, product_variant_code) GROUP BY p
), r AS (
  SELECT SUM(rev) AS rev30 FROM s WHERE p = 'tw' AND qty > 0
), m AS (
  SELECT 'Visible variants (sellable)' AS measure, 1 AS sort,
    MAX(IF(p = 'tw', visible, NULL)) AS variants, MAX(IF(p = 'ly', visible, NULL)) AS variants_ly,
    MAX(IF(p = 'tw', visible, NULL)) AS base, MAX(IF(p = 'ly', visible, NULL)) AS base_ly FROM a
  UNION ALL
  SELECT 'Productive (sold last 30d)', 2,
    MAX(IF(p = 'tw', productive, NULL)), MAX(IF(p = 'ly', productive, NULL)),
    MAX(IF(p = 'tw', visible, NULL)), MAX(IF(p = 'ly', visible, NULL)) FROM a
  UNION ALL
  SELECT 'Non-productive (no 30d sale)', 3,
    MAX(IF(p = 'tw', visible - productive, NULL)), MAX(IF(p = 'ly', visible - productive, NULL)),
    MAX(IF(p = 'tw', visible, NULL)), MAX(IF(p = 'ly', visible, NULL)) FROM a
)
SELECT measure, sort, variants,
  ROUND(SAFE_DIVIDE(variants, base), 4) AS share,
  variants_ly,
  ROUND(SAFE_DIVIDE(variants_ly, base_ly), 4) AS share_ly,
  ROUND(SAFE_DIVIDE(variants, variants_ly) - 1, 4) AS vs_ly_pct,
  ROUND(100 * (SAFE_DIVIDE(variants, base) - SAFE_DIVIDE(variants_ly, base_ly)), 2) AS share_vs_ly_pp,
  IF(sort = 2, ROUND(r.rev30, 2), NULL) AS rev_30d,
  IF(sort = 2, ROUND(SAFE_DIVIDE(r.rev30, variants), 2), NULL) AS rev_per_productive_30d,
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw)) AS week_end
FROM m CROSS JOIN r
ORDER BY sort
