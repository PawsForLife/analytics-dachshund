-- Dataset: pr_subcats
-- Title: Price position by category
-- Tab: Price
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: AD index, SKUs above market, KVI lines above market and revenue at risk by book and sub-category at the reporting Sunday, with book totals and a grand total. Reads product__price_component__eod, product__product_variant__eod, product__product_variant, customer__customer_order_basket, product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_end_date AS we FROM cal WHERE is_latest_merch_complete_week = TRUE),
pc AS (
  SELECT p.product_variant_code AS pvc, p.recurring_price AS ours,
    (SELECT MIN(c.competitor_price) FROM UNNEST(p.competitor_price_component) c
      WHERE c.price_type = 'Auto Delivery Price' AND c.is_latest_price_type_scrape AND c.competitor_price > 0
        AND c.competitor_marketplace = 'No Marketplace'
        AND c.competitor_name IN ('Petbarn', 'Petstock', 'PetO', 'Budget Pet Products')) AS mkt
  FROM `petcircle-warehouse-cloud.business_layer.product__price_component__eod` p
  CROSS JOIN r
  WHERE p.valid_for_date = r.we
),
grp AS (
  SELECT e.product_variant_code AS pvc, ANY_VALUE(e.multi_track_pricing_group) AS mtp
  FROM `petcircle-warehouse-cloud.business_layer.product__product_variant__eod` e
  CROSS JOIN r
  WHERE e.valid_for_date = r.we
  GROUP BY 1
),
pv AS (
  SELECT product_variant_code AS pvc, ANY_VALUE(category_description) AS sub_category
  FROM `petcircle-warehouse-cloud.business_layer.product__product_variant`
  GROUP BY 1
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
  GROUP BY 1
),
m AS (
  SELECT IFNULL(pv.sub_category, 'Unknown') AS sub_category, grp.mtp, pc.ours, pc.mkt, w.rev12, w.rev_lw,
    pc.ours > pc.mkt AS above
  FROM pc
  JOIN grp ON grp.pvc = pc.pvc
  JOIN w ON w.pvc = pc.pvc
  LEFT JOIN pv ON pv.pvc = pc.pvc
  WHERE pc.ours > 0 AND pc.mkt > 0 AND w.rev12 > 0 AND grp.mtp IN ('KVI', 'Core', 'Longtail')
),
bk AS (
  SELECT m.*,
    CASE
      WHEN sub_category IN ('Food', 'Treats', 'Chilled', 'Litter', 'Bundle Boxes', 'Better Bundle') THEN 'Core Consumables'
      WHEN sub_category IN ('Flea and Worming', 'Health', 'Grooming', 'Bird', 'Horse', 'Small Animal', 'Fish', 'Reptile') THEN 'Health & Other Species'
      WHEN sub_category IN ('Toys', 'Training and Clean Up', 'Housing and Bedding', 'Smart Pet Products', 'Apparel and Accessories', 'Car and Travel Accessories', 'Feeding and Watering') THEN 'Hardlines'
      ELSE 'Unmapped' END AS book
  FROM m
),
lv AS (
  SELECT book, sub_category, 0 AS lvl,
    SUM(rev12 * ours / mkt) / SUM(rev12) AS ad_index,
    COUNTIF(above) AS skus_above, COUNT(*) AS skus_matched,
    COUNTIF(above AND mtp = 'KVI') AS kvi_above,
    SUM(IF(above, rev_lw, 0)) AS revenue_at_risk
  FROM bk GROUP BY 1, 2
  UNION ALL
  SELECT book, 'Total', 1,
    SUM(rev12 * ours / mkt) / SUM(rev12), COUNTIF(above), COUNT(*), COUNTIF(above AND mtp = 'KVI'), SUM(IF(above, rev_lw, 0))
  FROM bk GROUP BY 1
  UNION ALL
  SELECT 'Total', 'Total', 2,
    SUM(rev12 * ours / mkt) / SUM(rev12), COUNTIF(above), COUNT(*), COUNTIF(above AND mtp = 'KVI'), SUM(IF(above, rev_lw, 0))
  FROM bk
),
tot AS (SELECT revenue_at_risk AS rar_total FROM lv WHERE lvl = 2)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  lv.book,
  CASE lv.book WHEN 'Core Consumables' THEN 1 WHEN 'Health & Other Species' THEN 2 WHEN 'Hardlines' THEN 3 WHEN 'Unmapped' THEN 4 ELSE 5 END AS book_sort,
  lv.sub_category,
  ROW_NUMBER() OVER (PARTITION BY lv.book ORDER BY lv.lvl, lv.revenue_at_risk DESC, lv.sub_category) AS sort,
  lv.lvl = 1 OR lv.lvl = 2 AS is_total,
  ROUND(lv.ad_index, 4) AS ad_index,
  lv.skus_above,
  lv.skus_matched,
  lv.kvi_above,
  ROUND(lv.revenue_at_risk, 2) AS revenue_at_risk,
  ROUND(SAFE_DIVIDE(lv.revenue_at_risk, tot.rar_total) * 100, 2) AS share_of_risk,
  FORMAT_DATE('%F', r.we) AS snapshot_date
FROM lv CROSS JOIN tot CROSS JOIN r
ORDER BY book_sort, lv.lvl, lv.revenue_at_risk DESC, lv.sub_category
