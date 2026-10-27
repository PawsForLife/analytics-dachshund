-- Dataset: cat_books
-- Title: Category performance by book
-- Tab: Category
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Reporting-week revenue, margin, plan, LY and 12-week average comparisons, PLEX and promo penetration for each merchandise book plus the total. Reads product__customer_order, customer__customer_order_basket, product__product_variant, product__targets_category_by_day, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT * FROM cal WHERE is_latest_merch_complete_week = TRUE),
ly AS (SELECT * FROM cal WHERE is_prior_year_latest_merch_complete_week = TRUE),
wk AS (
  SELECT c.week_start_date AS ws, c.week_end_date AS we,
    c.week_end_date = r.week_end_date AS is_tw,
    c.merch_cal_year_name = r.merch_cal_year_name AND c.merch_cal_month_number = r.merch_cal_month_number AND c.week_end_date <= r.week_end_date AS is_mtd,
    c.merch_cal_year_name = r.merch_cal_year_name AND c.week_end_date <= r.week_end_date AS is_ytd,
    c.week_end_date BETWEEN DATE_SUB(r.week_end_date, INTERVAL 84 DAY) AND DATE_SUB(r.week_end_date, INTERVAL 7 DAY) AS is_l12,
    c.week_end_date = ly.week_end_date AS is_ly_tw,
    c.merch_cal_year_name = ly.merch_cal_year_name AND c.merch_cal_month_number = ly.merch_cal_month_number AND c.week_end_date <= ly.week_end_date AS is_ly_mtd,
    c.merch_cal_year_name = ly.merch_cal_year_name AND c.week_end_date <= ly.week_end_date AS is_ly_ytd
  FROM cal c CROSS JOIN r CROSS JOIN ly
  WHERE c.week_end_date = ly.week_end_date
     OR c.week_end_date BETWEEN DATE_SUB(r.week_end_date, INTERVAL 84 DAY) AND r.week_end_date
),
rng AS (SELECT MIN(ws) AS d0, MAX(we) AS d1 FROM wk),
pv AS (
  SELECT product_variant_code, LOGICAL_OR(is_private_label_or_exclusive) AS plex
  FROM `petcircle-warehouse-cloud.business_layer.product__product_variant` GROUP BY 1
),
o AS (
  SELECT o.order_id, o.order_created_date AS d, o.is_auto_delivery_order AS is_ad
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o CROSS JOIN rng
  WHERE o.status != 'Cancelled' AND o.order_created_date BETWEEN rng.d0 AND rng.d1
),
lines AS (
  SELECT wk.we, IFNULL(b.category_description, 'Unknown') AS sub_category, o.is_ad,
    IFNULL(pv.plex, FALSE) AS plex, IFNULL(b.is_discount_applied, FALSE) AS disc,
    IFNULL(b.product_variant_revenue_complete_excl_gst, 0) AS rev,
    IFNULL(b.product_variant_margin_complete_excl_gst, 0) AS mg,
    IFNULL(b.quantity_complete, 0) AS qty,
    IFNULL(b.recurring_discount_amount_complete_excl_gst, 0) AS rd
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au') b
  CROSS JOIN rng
  JOIN o ON o.order_id = b.order_id
  JOIN wk ON o.d BETWEEN wk.ws AND wk.we
  LEFT JOIN pv ON pv.product_variant_code = b.product_variant_code
  WHERE b.order_created_date BETWEEN DATE_SUB(rng.d0, INTERVAL 7 DAY) AND DATE_ADD(rng.d1, INTERVAL 7 DAY)
),
aw AS (
  SELECT we, sub_category, SUM(rev) AS rev, SUM(mg) AS mg, SUM(qty) AS qty,
    SUM(IF(is_ad, 0, rev)) AS rev_tx, SUM(IF(NOT is_ad AND disc, rev, 0)) AS rev_tx_disc,
    SUM(IF(is_ad, rev, 0)) AS rev_ad, SUM(IF(is_ad, rd, 0)) AS rd,
    SUM(IF(plex, rev, 0)) AS rev_plex
  FROM lines GROUP BY 1, 2
),
pl AS (
  SELECT wk.we,
    CASE REGEXP_REPLACE(ARRAY_REVERSE(SPLIT(t.category_name, ' : '))[OFFSET(0)], r'^[A-Z](\.[A-Z])?\.? ', '')
      WHEN 'Bundle Boxes' THEN 'Better Bundle'
      ELSE REGEXP_REPLACE(ARRAY_REVERSE(SPLIT(t.category_name, ' : '))[OFFSET(0)], r'^[A-Z](\.[A-Z])?\.? ', '') END AS sub_category,
    SUM(t.daily_product_revenue_target) AS bud, SUM(t.daily_product_margin_target) AS mbud
  FROM `petcircle-warehouse-cloud.business_layer.product__targets_category_by_day` t
  JOIN wk ON t.calendar_date BETWEEN wk.ws AND wk.we
  GROUP BY 1, 2
),
j AS (
  SELECT wk.*, COALESCE(aw.sub_category, pl.sub_category) AS sub_category,
    aw.rev, aw.mg, aw.qty, aw.rev_tx, aw.rev_tx_disc, aw.rev_ad, aw.rd, aw.rev_plex, pl.bud, pl.mbud
  FROM aw FULL JOIN pl ON aw.we = pl.we AND aw.sub_category = pl.sub_category
  JOIN wk ON wk.we = COALESCE(aw.we, pl.we)
),
bk AS (
  SELECT j.*,
    CASE
      WHEN sub_category IN ('Food', 'Treats', 'Chilled', 'Litter', 'Bundle Boxes', 'Better Bundle') THEN 'Core Consumables'
      WHEN sub_category IN ('Flea and Worming', 'Health', 'Grooming', 'Bird', 'Horse', 'Small Animal', 'Fish', 'Reptile') THEN 'Health & Other Species'
      WHEN sub_category IN ('Toys', 'Training and Clean Up', 'Housing and Bedding', 'Smart Pet Products', 'Apparel and Accessories', 'Car and Travel Accessories', 'Feeding and Watering') THEN 'Hardlines'
      ELSE 'Unmapped' END AS book
  FROM j
),
g AS (
  SELECT IF(GROUPING(book) = 1, 'Total', book) AS bk,
    SUM(IF(is_tw, rev, 0)) AS rev, SUM(IF(is_tw, mg, 0)) AS mg,
    SUM(IF(is_tw, rev_tx, 0)) AS rev_tx, SUM(IF(is_tw, rev_tx_disc, 0)) AS rev_tx_disc,
    SUM(IF(is_tw, rev_plex, 0)) AS rev_plex,
    SUM(IF(is_tw, bud, NULL)) AS bud, SUM(IF(is_tw, mbud, NULL)) AS mbud,
    SUM(IF(is_ly_tw, rev, 0)) AS rev_ly, SUM(IF(is_ly_tw, mg, 0)) AS mg_ly,
    SUM(IF(is_l12, rev, 0)) / 12 AS rev_l12
  FROM bk
  GROUP BY GROUPING SETS ((book), ())
)
SELECT
  bk AS book,
  CASE bk WHEN 'Core Consumables' THEN 1 WHEN 'Health & Other Species' THEN 2 WHEN 'Hardlines' THEN 3 WHEN 'Unmapped' THEN 4 ELSE 9 END AS sort,
  ROUND(rev, 2) AS revenue,
  ROUND(rev_ly, 2) AS revenue_ly,
  ROUND(SAFE_DIVIDE(rev, NULLIF(rev_ly, 0)) - 1, 4) AS rev_vs_ly_pct,
  ROUND(SAFE_DIVIDE(rev, NULLIF(rev_l12, 0)) - 1, 4) AS rev_vs_l12w_pct,
  ROUND(bud, 2) AS budget,
  ROUND(rev - bud, 2) AS rev_vs_bud,
  ROUND(mg, 2) AS margin,
  ROUND(mbud, 2) AS margin_budget,
  ROUND(mg - mbud, 2) AS margin_vs_bud,
  ROUND(SAFE_DIVIDE(mg, NULLIF(rev, 0)), 4) AS pm_pct,
  ROUND(SAFE_DIVIDE(mg, NULLIF(rev, 0)) - SAFE_DIVIDE(mbud, NULLIF(bud, 0)), 4) AS pm_vs_bud_pp,
  ROUND(SAFE_DIVIDE(mg, NULLIF(rev, 0)) - SAFE_DIVIDE(mg_ly, NULLIF(rev_ly, 0)), 4) AS pm_vs_ly_pp,
  ROUND(SAFE_DIVIDE(rev_plex, NULLIF(rev, 0)), 4) AS plex_pen_pct,
  ROUND(SAFE_DIVIDE(rev_tx_disc, NULLIF(rev_tx, 0)), 4) AS promo_pen_tx_pct,
  (SELECT IF(merch_cal_quarter_name = 'Quarter 1', 'Budget', 'Forecast') FROM r) AS plan_label,
  (SELECT FORMAT_DATE('%F', week_end_date) FROM r) AS week_end
FROM g
WHERE bk != 'Unmapped' OR rev != 0
ORDER BY sort
