-- Dataset: mf_landing
-- Title: Landing surface deep dive
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Reporting-week sessions, mix, conversion and web funnel reach by first landing surface against the prior-12-week base. Reads online__session, product__brand, pet__species, reference__calendar_4_4_5_week.

WITH r AS (
  SELECT week_start_date AS ws, week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
wk AS (
  SELECT c.week_start_date, c.week_end_date, CAST(DATE_DIFF(r.ws, c.week_start_date, DAY) / 7 AS INT64) AS k
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` c CROSS JOIN r
  WHERE c.week_start_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.ws
),
lp AS (
  SELECT
    wk.k,
    j.digital_platform_type = 'Mobile App' AS app,
    j.landing_page_definition_name AS lpd,
    IF(j.landing_page_definition_name = 'Other',
      (SELECT REGEXP_EXTRACT(p.page_path, r'^(/[^/?]*)') FROM UNNEST(j.session_page) p WHERE p.is_entrance LIMIT 1), NULL) AS seg,
    IFNULL(j.session_count, 0) AS s,
    IFNULL(j.session_count_has_converted, 0) AS o,
    IF(j.digital_platform_type = 'Website', IFNULL(j.session_count, 0), 0) AS ws_,
    IF(j.digital_platform_type = 'Website', IFNULL(j.session_count_has_added_item_to_cart, 0), 0) AS atc,
    IF(j.digital_platform_type = 'Website', IFNULL(j.session_count_has_visited_cart, 0), 0) AS vc,
    IF(j.digital_platform_type = 'Website', IFNULL(j.session_count_has_visited_checkout, 0), 0) AS vco
  FROM `petcircle-warehouse-cloud.business_layer.online__session` j
  JOIN wk ON j.session_start_date BETWEEN wk.week_start_date AND wk.week_end_date
  WHERE j.bot_likelihood_category = 'Likely Human' AND j.business_line = 'Pet Circle'
    AND j.session_start_date BETWEEN (SELECT DATE_SUB(ws, INTERVAL 84 DAY) FROM r) AND (SELECT we FROM r)
),
bs AS (
  SELECT DISTINCT CONCAT('/', TRIM(REGEXP_REPLACE(REGEXP_REPLACE(LOWER(n), r'[\x{0027}\x{2019}.!&+]', ''), r'[^a-z0-9]+', '-'), '-')) AS slug
  FROM `petcircle-warehouse-cloud.business_layer.product__brand`, UNNEST([brand, display_brand_name]) n WHERE n IS NOT NULL
),
sp AS (
  SELECT DISTINCT CONCAT('/', TRIM(REGEXP_REPLACE(LOWER(species), r'[^a-z0-9]+', '-'), '-')) AS slug
  FROM `petcircle-warehouse-cloud.business_layer.pet__species` WHERE species IS NOT NULL
),
m AS (
  SELECT lp.k, lp.app, lp.s, lp.o, lp.ws_, lp.atc, lp.vc, lp.vco,
    CASE
      WHEN lp.app THEN 'Mobile App'
      WHEN lp.lpd IS NULL THEN 'Unknown'
      WHEN lp.lpd = 'Product Detail Page' THEN 'PDP'
      WHEN lp.lpd = 'Home Page' OR (lp.lpd = 'Other' AND lp.seg = '/') THEN 'Homepage'
      WHEN lp.lpd IN ('Order Mgt Page', 'My Pet Page', 'AD Re-Order Confirmation Page')
        OR (lp.lpd = 'Other' AND (STARTS_WITH(lp.seg, '/account') OR lp.seg IN ('/sign-in', '/resetpassword'))) THEN 'Account'
      WHEN lp.lpd IN ('Landing Page', 'Collection Page', 'Sales Page (Browse)') THEN 'Promo / Landing'
      WHEN lp.lpd IN ('Pet Type Page (Browse)', 'Species Page') OR sp.slug IS NOT NULL THEN 'Pet Type PLP'
      WHEN lp.lpd = 'Brand Page (Browse)' OR bs.slug IS NOT NULL THEN 'Brand PLP'
      WHEN lp.lpd = 'Discover Page' THEN 'Discover'
      WHEN lp.lpd = 'Search Result Page' THEN 'Search'
      WHEN lp.lpd = 'Cart Page' THEN 'Cart'
      WHEN lp.lpd = 'Checkout Page' THEN 'Checkout'
      WHEN lp.lpd = 'Thanks Page' THEN 'Thanks'
      ELSE 'Other'
    END AS surface
  FROM lp
  LEFT JOIN bs ON lp.lpd = 'Other' AND lp.seg = bs.slug
  LEFT JOIN sp ON lp.lpd = 'Other' AND lp.seg = sp.slug
),
nb AS (SELECT COUNT(DISTINCT k) AS n FROM m WHERE k BETWEEN 1 AND 12),
a AS (
  SELECT surface, LOGICAL_AND(app) AS app_only,
    SUM(IF(k = 0, s, 0)) AS s_t, SUM(IF(k BETWEEN 1 AND 12, s, 0)) AS s_b,
    SUM(IF(k = 0, o, 0)) AS o_t, SUM(IF(k BETWEEN 1 AND 12, o, 0)) AS o_b,
    SUM(IF(k = 0, ws_, 0)) AS ws_t, SUM(IF(k = 0, atc, 0)) AS atc_t,
    SUM(IF(k = 0, vc, 0)) AS vc_t, SUM(IF(k = 0, vco, 0)) AS vco_t
  FROM m GROUP BY 1
),
t AS (SELECT SUM(s_t) AS s_t, SUM(s_b) AS s_b FROM a)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  a.surface,
  CAST(ROW_NUMBER() OVER (ORDER BY a.s_t DESC, a.surface) AS INT64) AS sort,
  a.s_t AS sessions,
  ROUND(a.s_b / nb.n, 1) AS sessions_l12w,
  ROUND(SAFE_DIVIDE(a.s_t, a.s_b / nb.n) - 1, 4) AS sessions_vs_l12w_pct,
  ROUND(100 * SAFE_DIVIDE(a.s_t, t.s_t), 4) AS mix,
  ROUND(100 * (SAFE_DIVIDE(a.s_t, t.s_t) - SAFE_DIVIDE(a.s_b, t.s_b)), 4) AS mix_pp,
  ROUND(100 * SAFE_DIVIDE(a.o_t, a.s_t), 4) AS cvr,
  ROUND(100 * (SAFE_DIVIDE(a.o_t, a.s_t) - SAFE_DIVIDE(a.o_b, a.s_b)), 4) AS cvr_pp,
  IF(a.app_only, NULL, ROUND(100 * SAFE_DIVIDE(a.atc_t, a.ws_t), 4)) AS atc,
  IF(a.app_only, NULL, ROUND(100 * SAFE_DIVIDE(a.vc_t, a.ws_t), 4)) AS cart,
  IF(a.app_only, NULL, ROUND(100 * SAFE_DIVIDE(a.vco_t, a.ws_t), 4)) AS checkout,
  a.o_t AS orders,
  nb.n AS l12w_weeks
FROM a CROSS JOIN t CROSS JOIN nb CROSS JOIN r
WHERE a.s_t > 0
ORDER BY sort
