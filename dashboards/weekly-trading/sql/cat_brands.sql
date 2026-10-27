-- Dataset: cat_brands
-- Title: Brand movers by book
-- Tab: Category
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Per book, the three brands growing fastest and the three slowest against the same 445 week LY, among brands above the weekly revenue floor, with vs last week and vs 13-week average. Reads product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT * FROM cal WHERE is_latest_merch_complete_week = TRUE),
ly AS (SELECT * FROM cal WHERE is_prior_year_latest_merch_complete_week = TRUE),
wk AS (
  SELECT c.week_start_date AS ws, c.week_end_date AS we,
    c.week_end_date = r.week_end_date AS is_tw,
    c.week_end_date = DATE_SUB(r.week_end_date, INTERVAL 7 DAY) AS is_lw,
    c.week_end_date BETWEEN DATE_SUB(r.week_end_date, INTERVAL 91 DAY) AND DATE_SUB(r.week_end_date, INTERVAL 7 DAY) AS is_l13,
    c.week_end_date = ly.week_end_date AS is_ly
  FROM cal c CROSS JOIN r CROSS JOIN ly
  WHERE c.week_end_date = ly.week_end_date
     OR c.week_end_date BETWEEN DATE_SUB(r.week_end_date, INTERVAL 91 DAY) AND r.week_end_date
),
o AS (
  SELECT o.order_id, wk.*
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk ON o.order_created_date BETWEEN wk.ws AND wk.we
  WHERE o.status != 'Cancelled'
    AND o.order_created_date >= (SELECT MIN(ws) FROM wk) AND o.order_created_date <= (SELECT MAX(we) FROM wk)
),
lines AS (
  SELECT o.is_tw, o.is_lw, o.is_l13, o.is_ly, TRIM(b.brand) AS brand,
    CASE
      WHEN b.category_description IN ('Food', 'Treats', 'Chilled', 'Litter', 'Bundle Boxes', 'Better Bundle') THEN 'Core Consumables'
      WHEN b.category_description IN ('Flea and Worming', 'Health', 'Grooming', 'Bird', 'Horse', 'Small Animal', 'Fish', 'Reptile') THEN 'Health & Other Species'
      WHEN b.category_description IN ('Toys', 'Training and Clean Up', 'Housing and Bedding', 'Smart Pet Products', 'Apparel and Accessories', 'Car and Travel Accessories', 'Feeding and Watering') THEN 'Hardlines'
      ELSE 'Unmapped' END AS book,
    IFNULL(b.product_variant_revenue_complete_excl_gst, 0) AS rev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au') b
  JOIN o ON o.order_id = b.order_id
  WHERE b.order_created_date >= DATE_SUB((SELECT MIN(ws) FROM wk), INTERVAL 7 DAY)
    AND b.order_created_date <= DATE_ADD((SELECT MAX(we) FROM wk), INTERVAL 7 DAY)
    AND b.brand IS NOT NULL AND TRIM(b.brand) != ''
),
ag AS (
  SELECT book, brand,
    SUM(IF(is_tw, rev, 0)) AS rev, SUM(IF(is_lw, rev, 0)) AS rev_lw,
    SUM(IF(is_l13, rev, 0)) / 13 AS rev_l13, SUM(IF(is_ly, rev, 0)) AS rev_ly
  FROM lines GROUP BY 1, 2
),
el AS (
  SELECT ag.*,
    CASE book WHEN 'Hardlines' THEN 2000 ELSE 15000 END AS floor_rev
  FROM ag
  WHERE book != 'Unmapped'
),
sc AS (
  SELECT el.*, SAFE_DIVIDE(rev, rev_ly) - 1 AS g, COUNT(*) OVER (PARTITION BY book) AS brands_above_floor
  FROM el WHERE rev >= floor_rev AND rev_ly > 0
),
rk AS (
  SELECT sc.*,
    ROW_NUMBER() OVER (PARTITION BY book ORDER BY g DESC, brand) AS rk_up,
    ROW_NUMBER() OVER (PARTITION BY book ORDER BY g ASC, brand) AS rk_dn
  FROM sc
),
x AS (
  SELECT 'up' AS direction, rk_up AS rnk, rk.* FROM rk WHERE rk_up <= 3
  UNION ALL
  SELECT 'down', rk_dn, rk.* FROM rk WHERE rk_dn <= 3 AND rk_up > 3
)
SELECT
  book,
  CASE book WHEN 'Core Consumables' THEN 1 WHEN 'Health & Other Species' THEN 2 ELSE 3 END AS book_sort,
  direction,
  rnk AS rank,
  brand,
  ROUND(rev, 2) AS revenue,
  ROUND(g, 4) AS rev_vs_ly_pct,
  ROUND(SAFE_DIVIDE(rev, NULLIF(rev_lw, 0)) - 1, 4) AS rev_vs_lw_pct,
  ROUND(SAFE_DIVIDE(rev, NULLIF(rev_l13, 0)) - 1, 4) AS rev_vs_13w_pct,
  brands_above_floor,
  (SELECT FORMAT_DATE('%F', week_end_date) FROM r) AS week_end
FROM x
ORDER BY book_sort, IF(direction = 'up', 1, 2), rnk
