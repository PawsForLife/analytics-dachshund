-- Dataset: pr_discounts
-- Title: Discount and funding waterfall
-- Tab: Price
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Reporting-week gross revenue, every customer-facing discount by type, supplier TPD cofunding and the margin drag by book, tied to product revenue on the Commercial scorecard. Reads product__customer_order (nested customer_order_basket and customer_order_basket_discounts), product__price_component__eod, product__promotion_temporary_price_discount__eod, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_start_date AS ws, week_end_date AS we FROM cal WHERE is_latest_merch_complete_week = TRUE),
ly AS (SELECT week_start_date AS ws, week_end_date AS we FROM cal WHERE is_prior_year_latest_merch_complete_week = TRUE),
wk AS (
  SELECT 'TW' AS p, ws, we FROM r
  UNION ALL SELECT 'LY', ws, we FROM ly
),
ln AS (
  SELECT wk.p, o.order_created_date AS d, b.product_variant_code AS pvc,
    IFNULL(b.category_description, 'Unknown') AS sub_category,
    IFNULL(b.quantity_complete, 0) AS q,
    IFNULL(b.product_variant_revenue_complete_excl_gst, 0) AS rev,
    IFNULL(b.product_variant_margin_complete_excl_gst, 0) AS mg,
    IFNULL(b.auto_delivery_rebate_amount_complete_excl_gst, 0) AS ad_rebate,
    (SELECT AS STRUCT
        IFNULL(SUM(IF(x.discount_categorisation = 'Coupon', x.discount_amount_complete_excl_gst, 0)), 0) AS coupon,
        IFNULL(SUM(IF(x.discount_categorisation != 'Coupon' AND x.discount_subtype = 'recurring-ad-savings', x.discount_amount_complete_excl_gst, 0)), 0) AS ad_rec,
        IFNULL(SUM(IF(x.discount_categorisation != 'Coupon' AND x.discount_subtype = 'ad-incentive-offer', x.discount_amount_complete_excl_gst, 0)), 0) AS ad_inc,
        IFNULL(SUM(IF(x.discount_categorisation != 'Coupon' AND x.discount_subtype = 'price-match', x.discount_amount_complete_excl_gst, 0)), 0) AS pm,
        IFNULL(SUM(IF(x.discount_categorisation != 'Coupon' AND IFNULL(x.discount_subtype, '') NOT IN ('recurring-ad-savings', 'ad-incentive-offer', 'price-match'), x.discount_amount_complete_excl_gst, 0)), 0) AS oth
      FROM UNNEST(b.customer_order_basket_discounts) x) AS ds,
    o.is_auto_delivery_order AS is_ad
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk ON o.order_created_date BETWEEN wk.ws AND wk.we
  CROSS JOIN UNNEST(o.customer_order_basket) b
  WHERE o.status != 'Cancelled'
    AND o.order_created_date BETWEEN (SELECT MIN(ws) FROM wk) AND (SELECT MAX(we) FROM wk)
),
pc AS (
  SELECT p.product_variant_code AS pvc, p.valid_for_date AS d, p.once_off_price AS oop
  FROM `petcircle-warehouse-cloud.business_layer.product__price_component__eod` p
  JOIN wk ON p.valid_for_date BETWEEN wk.ws AND wk.we
  WHERE p.valid_for_date BETWEEN (SELECT MIN(ws) FROM wk) AND (SELECT MAX(we) FROM wk)
    AND p.temporary_discount_price IS NOT NULL
),
tp AS (
  SELECT t.product_variant_code AS pvc, t.valid_for_date AS d,
    MAX(t.temporary_price_discount_cofunded_amount_per_unit_excl_gst) AS cof_pu
  FROM `petcircle-warehouse-cloud.business_layer.product__promotion_temporary_price_discount__eod` t
  JOIN wk ON t.valid_for_date BETWEEN wk.ws AND wk.we
  WHERE t.valid_for_date BETWEEN (SELECT MIN(ws) FROM wk) AND (SELECT MAX(we) FROM wk)
  GROUP BY 1, 2
),
j AS (
  SELECT ln.*,
    IF(pc.pvc IS NOT NULL, GREATEST(0, pc.oop * ln.q / 1.1 - ln.rev), 0) AS tpd
  FROM ln
  LEFT JOIN pc ON pc.pvc = ln.pvc AND pc.d = ln.d
),
j2 AS (
  SELECT j.*, IF(j.tpd > 0, IFNULL(tp.cof_pu, 0) * j.q, 0) AS cof
  FROM j LEFT JOIN tp ON tp.pvc = j.pvc AND tp.d = j.d
),
bk AS (
  SELECT j2.*,
    CASE
      WHEN sub_category IN ('Food', 'Treats', 'Chilled', 'Litter', 'Bundle Boxes', 'Better Bundle') THEN 'Core Consumables'
      WHEN sub_category IN ('Flea and Worming', 'Health', 'Grooming', 'Bird', 'Horse', 'Small Animal', 'Fish', 'Reptile') THEN 'Health & Other Species'
      WHEN sub_category IN ('Toys', 'Training and Clean Up', 'Housing and Bedding', 'Smart Pet Products', 'Apparel and Accessories', 'Car and Travel Accessories', 'Feeding and Watering') THEN 'Hardlines'
      ELSE 'Unmapped' END AS book
  FROM j2
),
g AS (
  SELECT IF(lvl = 1, 'Total', book) AS book, lvl, p,
    SUM(rev) AS product_revenue, SUM(mg) AS product_margin, SUM(tpd) AS tpd,
    SUM(IF(NOT is_ad, tpd, 0)) AS tpd_nonad, SUM(cof) AS cof, SUM(IF(NOT is_ad, cof, 0)) AS cof_nonad,
    SUM(ds.coupon) AS coupon, SUM(ds.ad_rec) AS ad_rec, SUM(ds.ad_inc) AS ad_inc, SUM(ds.pm) AS pm, SUM(ds.oth) AS oth,
    SUM(ad_rebate) AS ad_rebate
  FROM bk CROSS JOIN UNNEST([0, 1]) AS lvl
  GROUP BY 1, 2, 3
),
f AS (
  SELECT t.*, t.tpd + t.coupon + t.ad_rec + t.ad_inc + t.pm + t.oth AS total_disc,
    l.tpd + l.coupon + l.ad_rec + l.ad_inc + l.pm + l.oth AS total_disc_ly,
    l.product_revenue AS product_revenue_ly, l.tpd AS tpd_ly, l.ad_rec AS ad_rec_ly, l.coupon AS coupon_ly
  FROM (SELECT * FROM g WHERE p = 'TW') t
  LEFT JOIN (SELECT * FROM g WHERE p = 'LY') l ON l.book = t.book
)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  f.book,
  CASE f.book WHEN 'Core Consumables' THEN 1 WHEN 'Health & Other Species' THEN 2 WHEN 'Hardlines' THEN 3 WHEN 'Unmapped' THEN 4 ELSE 5 END AS sort,
  f.lvl = 1 AS is_total,
  ROUND(f.product_revenue + f.tpd, 2) AS gross_revenue,
  ROUND(f.product_revenue, 2) AS product_revenue,
  ROUND(f.tpd, 2) AS tpd_discount,
  ROUND(SAFE_DIVIDE(f.tpd, f.product_revenue + f.tpd) * 100, 4) AS tpd_pct,
  ROUND(f.coupon, 2) AS coupon_discount,
  ROUND(f.ad_rec, 2) AS ad_recurring_discount,
  ROUND(f.ad_inc, 2) AS ad_incentive_discount,
  ROUND(f.pm, 2) AS price_match_discount,
  ROUND(f.oth, 2) AS other_discount,
  ROUND(f.total_disc, 2) AS total_discount,
  ROUND(SAFE_DIVIDE(f.total_disc, f.product_revenue + f.tpd) * 100, 4) AS discount_pct,
  ROUND(f.coupon + f.ad_rec + f.ad_inc + f.pm + f.oth, 2) AS discounts_outside_product_revenue,
  ROUND(f.cof, 2) AS cofunding,
  ROUND(SAFE_DIVIDE(f.cof, f.tpd) * 100, 4) AS cofund_recovery_pct,
  ROUND(f.tpd_nonad, 2) AS tpd_discount_nonad,
  ROUND(f.cof_nonad, 2) AS cofunding_nonad,
  ROUND(SAFE_DIVIDE(f.cof_nonad, f.tpd_nonad) * 100, 4) AS cofund_recovery_pct_nonad,
  ROUND(f.ad_rebate, 2) AS ad_supplier_rebate,
  ROUND(f.product_margin, 2) AS product_margin,
  ROUND(SAFE_DIVIDE(f.product_margin, f.product_revenue) * 100, 4) AS pm_pct,
  ROUND(SAFE_DIVIDE(f.product_margin + f.tpd + f.ad_rec, f.product_revenue + f.tpd) * 100, 4) AS pm_pct_ex_discount,
  ROUND((SAFE_DIVIDE(f.product_margin, f.product_revenue) - SAFE_DIVIDE(f.product_margin + f.tpd + f.ad_rec, f.product_revenue + f.tpd)) * 10000, 1) AS discount_drag_bps,
  ROUND(f.total_disc_ly, 2) AS total_discount_ly,
  ROUND(f.tpd_ly, 2) AS tpd_discount_ly,
  ROUND(f.ad_rec_ly, 2) AS ad_recurring_discount_ly,
  ROUND(f.coupon_ly, 2) AS coupon_discount_ly,
  ROUND(SAFE_DIVIDE(f.total_disc, f.total_disc_ly) - 1, 4) AS discount_vs_ly_pct,
  ROUND(SAFE_DIVIDE(f.total_disc_ly, f.product_revenue_ly + f.tpd_ly) * 100, 4) AS discount_pct_ly,
  ROUND((SAFE_DIVIDE(f.total_disc, f.product_revenue + f.tpd) - SAFE_DIVIDE(f.total_disc_ly, f.product_revenue_ly + f.tpd_ly)) * 100, 4) AS discount_pct_vs_ly_pp
FROM f CROSS JOIN r
ORDER BY sort
