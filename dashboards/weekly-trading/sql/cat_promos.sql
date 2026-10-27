-- Dataset: cat_promos
-- Title: Promotional performance
-- Tab: Category
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: One row per brand-level TPD promotional campaign (wave of at most 35 days) that ended in the last 6 weeks or is still running, with funding, transactional and AD unit lift during and after the flag, margin with and without supplier funding, and a rule-based cohort. Reads product__promotion_temporary_price_discount__eod, product__product_variant, product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_end_date AS rwe FROM cal WHERE is_latest_merch_complete_week = TRUE),
pv AS (
  SELECT product_variant_code, ANY_VALUE(TRIM(brand)) AS brand,
    CASE
      WHEN ANY_VALUE(category_description) IN ('Food', 'Treats', 'Chilled', 'Litter', 'Bundle Boxes', 'Better Bundle') THEN 'Core Consumables'
      WHEN ANY_VALUE(category_description) IN ('Flea and Worming', 'Health', 'Grooming', 'Bird', 'Horse', 'Small Animal', 'Fish', 'Reptile') THEN 'Health & Other Species'
      WHEN ANY_VALUE(category_description) IN ('Toys', 'Training and Clean Up', 'Housing and Bedding', 'Smart Pet Products', 'Apparel and Accessories', 'Car and Travel Accessories', 'Feeding and Watering') THEN 'Hardlines'
      ELSE 'Unmapped' END AS book
  FROM `petcircle-warehouse-cloud.business_layer.product__product_variant`
  GROUP BY 1
),
f AS (
  SELECT t.valid_for_date AS d, t.product_variant_code,
    MAX(IFNULL(t.temporary_price_discount_amount_per_unit_excl_gst, 0)) AS disc_u,
    MAX(IFNULL(t.temporary_price_discount_cofunded_amount_per_unit_excl_gst, 0)) AS fund_u
  FROM `petcircle-warehouse-cloud.business_layer.product__promotion_temporary_price_discount__eod` t CROSS JOIN r
  WHERE t.valid_for_date BETWEEN DATE_SUB(r.rwe, INTERVAL 182 DAY) AND r.rwe
  GROUP BY 1, 2
),
bd AS (
  SELECT pv.brand, f.d FROM f JOIN pv USING (product_variant_code)
  WHERE pv.brand IS NOT NULL AND pv.brand != '' GROUP BY 1, 2
),
bg AS (
  SELECT brand, d, IF(DATE_DIFF(d, LAG(d) OVER (PARTITION BY brand ORDER BY d), DAY) - 1 > 3 OR LAG(d) OVER (PARTITION BY brand ORDER BY d) IS NULL, 1, 0) AS nw
  FROM bd
),
bw AS (
  SELECT brand, d, SUM(nw) OVER (PARTITION BY brand ORDER BY d) AS wid FROM bg
),
wv0 AS (
  SELECT brand, wid, MIN(d) AS sd, MAX(d) AS ed FROM bw GROUP BY 1, 2
),
wv AS (
  SELECT wv0.*, LEAD(sd) OVER (PARTITION BY brand ORDER BY sd) AS nsd, r.rwe,
    DATE_DIFF(ed, sd, DAY) + 1 AS days,
    ed >= r.rwe AS is_running,
    LEAST(IFNULL(DATE_SUB(LEAD(sd) OVER (PARTITION BY brand ORDER BY sd), INTERVAL 1 DAY), r.rwe), r.rwe, DATE_ADD(ed, INTERVAL 28 DAY)) AS ped
  FROM wv0 CROSS JOIN r
),
ws AS (
  SELECT * FROM wv WHERE ed >= DATE_SUB(rwe, INTERVAL 41 DAY) AND sd > DATE_SUB(rwe, INTERVAL 182 DAY) AND days <= 35
),
sk AS (
  SELECT DISTINCT ws.brand, ws.wid, f.product_variant_code
  FROM ws JOIN pv ON pv.brand = ws.brand
  JOIN f ON f.product_variant_code = pv.product_variant_code AND f.d BETWEEN ws.sd AND ws.ed
),
rng AS (SELECT DATE_SUB(MIN(sd), INTERVAL 28 DAY) AS d0, MAX(rwe) AS d1 FROM ws),
o AS (
  SELECT o.order_id, o.order_created_date AS d, o.is_auto_delivery_order AS is_ad
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o CROSS JOIN rng
  WHERE o.status != 'Cancelled' AND o.order_created_date BETWEEN rng.d0 AND rng.d1
),
ln AS (
  SELECT o.d, o.is_ad, b.product_variant_code, pv.book,
    IFNULL(b.product_variant_revenue_complete_excl_gst, 0) AS rev,
    IFNULL(b.product_variant_margin_complete_excl_gst, 0) AS mg,
    IFNULL(b.quantity_complete, 0) AS qty
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au') b
  CROSS JOIN rng
  JOIN o ON o.order_id = b.order_id
  LEFT JOIN pv ON pv.product_variant_code = b.product_variant_code
  WHERE b.order_created_date BETWEEN DATE_SUB(rng.d0, INTERVAL 7 DAY) AND DATE_ADD(rng.d1, INTERVAL 7 DAY)
),
bk AS (
  SELECT d, book, SUM(rev) AS rev, SUM(mg) AS mg FROM ln GROUP BY 1, 2
),
dv AS (
  SELECT ln.d, ln.product_variant_code,
    SUM(IF(ln.is_ad, 0, ln.qty)) AS u_tx, SUM(IF(ln.is_ad, ln.qty, 0)) AS u_ad,
    SUM(ln.rev) AS rev, SUM(ln.mg) AS mg,
    SUM(ln.qty) * ANY_VALUE(IFNULL(f.fund_u, 0)) AS fund,
    SUM(ln.qty) * ANY_VALUE(IFNULL(f.disc_u, 0)) AS disc
  FROM ln
  LEFT JOIN f ON f.product_variant_code = ln.product_variant_code AND f.d = ln.d
  WHERE ln.product_variant_code IN (SELECT product_variant_code FROM sk)
  GROUP BY 1, 2
),
wm AS (
  SELECT ws.brand, ws.wid,
    SUM(IF(dv.d BETWEEN DATE_SUB(ws.sd, INTERVAL 28 DAY) AND DATE_SUB(ws.sd, INTERVAL 1 DAY), dv.u_tx, 0)) / 28 AS pre_tx,
    SUM(IF(dv.d BETWEEN DATE_SUB(ws.sd, INTERVAL 28 DAY) AND DATE_SUB(ws.sd, INTERVAL 1 DAY), dv.u_ad, 0)) / 28 AS pre_ad,
    SUM(IF(dv.d BETWEEN ws.sd AND LEAST(ws.ed, ws.rwe), dv.u_tx, 0)) / (DATE_DIFF(LEAST(ws.ed, ws.rwe), ws.sd, DAY) + 1) AS dur_tx,
    SUM(IF(dv.d BETWEEN ws.sd AND LEAST(ws.ed, ws.rwe), dv.u_ad, 0)) / (DATE_DIFF(LEAST(ws.ed, ws.rwe), ws.sd, DAY) + 1) AS dur_ad,
    SAFE_DIVIDE(SUM(IF(dv.d > ws.ed AND dv.d <= ws.ped, dv.u_tx, 0)), DATE_DIFF(ws.ped, ws.ed, DAY)) AS post_tx,
    SAFE_DIVIDE(SUM(IF(dv.d > ws.ed AND dv.d <= ws.ped, dv.u_ad, 0)), DATE_DIFF(ws.ped, ws.ed, DAY)) AS post_ad,
    SUM(IF(dv.d BETWEEN ws.sd AND ws.ed, dv.rev, 0)) AS rev_d,
    SUM(IF(dv.d BETWEEN ws.sd AND ws.ed, dv.mg, 0)) AS mg_d,
    SUM(IF(dv.d BETWEEN ws.sd AND ws.ed, dv.fund, 0)) AS fund_d,
    SUM(IF(dv.d BETWEEN ws.sd AND ws.ed, dv.disc, 0)) AS disc_d
  FROM ws
  JOIN sk ON sk.brand = ws.brand AND sk.wid = ws.wid
  JOIN dv ON dv.product_variant_code = sk.product_variant_code
    AND dv.d BETWEEN DATE_SUB(ws.sd, INTERVAL 28 DAY) AND ws.ped
  GROUP BY ws.brand, ws.wid, ws.sd, ws.ed, ws.ped, ws.rwe
),
wb AS (
  SELECT sk.brand, sk.wid,
    APPROX_TOP_COUNT(pv.book, 1)[OFFSET(0)].value AS book
  FROM sk JOIN pv USING (product_variant_code) GROUP BY 1, 2
),
bpm AS (
  SELECT ws.brand, ws.wid, SAFE_DIVIDE(SUM(bk.mg), SUM(bk.rev)) AS book_pm
  FROM ws JOIN wb USING (brand, wid)
  JOIN bk ON bk.book = wb.book AND bk.d BETWEEN ws.sd AND LEAST(ws.ed, ws.rwe)
  GROUP BY 1, 2
),
a AS (
  SELECT ws.*, wb.book, bpm.book_pm, wm.* EXCEPT (brand, wid),
    SAFE_DIVIDE(wm.dur_tx, NULLIF(wm.pre_tx, 0)) - 1 AS d_tx,
    SAFE_DIVIDE(wm.dur_ad, NULLIF(wm.pre_ad, 0)) - 1 AS d_ad,
    IF(ws.is_running, NULL, SAFE_DIVIDE(wm.post_tx, NULLIF(wm.pre_tx, 0)) - 1) AS p_tx,
    IF(ws.is_running, NULL, SAFE_DIVIDE(wm.post_ad, NULLIF(wm.pre_ad, 0)) - 1) AS p_ad,
    SAFE_DIVIDE(wm.mg_d, NULLIF(wm.rev_d, 0)) AS pm_d,
    SAFE_DIVIDE(wm.mg_d + wm.fund_d, NULLIF(wm.rev_d, 0)) AS pm_f,
    SAFE_DIVIDE(wm.fund_d, NULLIF(wm.disc_d, 0)) AS fpct
  FROM ws JOIN wm USING (brand, wid) LEFT JOIN wb USING (brand, wid) LEFT JOIN bpm USING (brand, wid)
),
top AS (
  SELECT a.*, ROW_NUMBER() OVER (ORDER BY rev_d DESC) AS rn FROM a
),
t2 AS (
  SELECT top.*, COUNT(*) OVER (PARTITION BY brand) AS nb, ROW_NUMBER() OVER (PARTITION BY brand ORDER BY sd) AS kb
  FROM top WHERE rn <= 20
)
SELECT
  IF(nb > 1 AND kb > 1, CONCAT(brand, ' wave ', CAST(kb AS STRING)), brand) AS promotion,
  CONCAT(
    IF(EXTRACT(MONTH FROM sd) = EXTRACT(MONTH FROM ed), CAST(EXTRACT(DAY FROM sd) AS STRING), CONCAT(CAST(EXTRACT(DAY FROM sd) AS STRING), FORMAT_DATE(' %b', sd))),
    '-', CAST(EXTRACT(DAY FROM ed) AS STRING), FORMAT_DATE(' %b', ed),
    IF(is_running, ' - running', CONCAT(', ', CAST(days AS STRING), 'd'))) AS window_label,
  FORMAT_DATE('%F', sd) AS start_date,
  FORMAT_DATE('%F', ed) AS end_date,
  days,
  IF(is_running, 'running', 'scored') AS status,
  book,
  ROUND(rev_d, 2) AS during_revenue,
  ROUND(fpct, 4) AS funded_pct,
  ROUND(d_tx, 4) AS during_tx_vs_pre,
  ROUND(d_ad, 4) AS during_ad_vs_pre,
  ROUND(p_tx, 4) AS post_tx_vs_pre,
  ROUND(p_ad, 4) AS post_ad_vs_pre,
  IF(is_running, NULL, DATE_DIFF(ped, ed, DAY)) AS post_days,
  ROUND(pm_d, 4) AS pm_during,
  ROUND(pm_f, 4) AS pm_incl_funding,
  ROUND(book_pm, 4) AS book_pm,
  CASE
    WHEN is_running THEN 'Pending'
    WHEN p_tx IS NULL OR d_tx IS NULL THEN 'Not scored'
    WHEN d_tx < 0 AND p_tx < 0 THEN 'Loser'
    WHEN p_tx >= 0 AND pm_f >= book_pm THEN 'Winner'
    WHEN p_tx >= 0 THEN 'Winner - low margin'
    WHEN pm_f < book_pm THEN 'Giveaway'
    WHEN d_tx >= 0.2 THEN 'Volume Driver'
    ELSE 'Churner' END AS cohort,
  ROW_NUMBER() OVER (ORDER BY is_running, ed DESC, rev_d DESC) AS sort,
  FORMAT_DATE('%F', rwe) AS week_end
FROM t2
ORDER BY sort
