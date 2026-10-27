-- Dataset: mf_funnel
-- Title: Funnel metric matrix
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Web-only funnel rates by channel (visited cart, cart to checkout, checkout to thanks, cart to thanks, bounce, add to cart) and session mix against the prior-12-week base, with the cart-dependent bases cleaned of a tracking break. Reads online__session, reference__calendar_4_4_5_week.

WITH r AS (
  SELECT week_start_date AS ws, week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
wk AS (
  SELECT c.week_start_date, c.week_end_date, CAST(DATE_DIFF(r.ws, c.week_start_date, DAY) / 7 AS INT64) AS k
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` c CROSS JOIN r
  WHERE c.week_start_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.ws
),
m AS (
  SELECT
    wk.k,
    wk.week_start_date AS week_start,
    CASE
      WHEN j.digital_platform_type = 'Mobile App' THEN 'Mobile App'
      WHEN j.acquisition_channel_group IN ('SEM', 'Social', 'SEO', 'Email', 'Direct', 'SMS') THEN j.acquisition_channel_group
      ELSE 'Other'
    END AS channel,
    j.digital_platform_type = 'Website' AS web,
    j.session_count AS s,
    IF(j.digital_platform_type = 'Website', j.session_count, 0) AS ws_,
    IF(j.digital_platform_type = 'Website', j.session_count_has_added_item_to_cart, 0) AS atc,
    IF(j.digital_platform_type = 'Website', j.session_count_has_visited_cart, 0) AS vc,
    IF(j.digital_platform_type = 'Website', j.session_count_has_visited_checkout, 0) AS vco,
    IF(j.digital_platform_type = 'Website', j.session_count_has_visited_cart_and_checkout, 0) AS vcc,
    IF(j.digital_platform_type = 'Website' AND j.has_visited_checkout AND j.has_visited_thanks_page, j.session_count, 0) AS vct,
    IF(j.digital_platform_type = 'Website' AND IFNULL(j.page_view_count, 0) <= 1, j.session_count, 0) AS bnc
  FROM `petcircle-warehouse-cloud.business_layer.online__session` j
  JOIN wk ON j.session_start_date BETWEEN wk.week_start_date AND wk.week_end_date
  WHERE j.bot_likelihood_category = 'Likely Human' AND j.business_line = 'Pet Circle'
    AND j.session_start_date BETWEEN (SELECT DATE_SUB(ws, INTERVAL 84 DAY) FROM r) AND (SELECT we FROM r)
),
wkr AS (
  SELECT k, week_start, SAFE_DIVIDE(SUM(vc), SUM(ws_)) AS vc_rate FROM m WHERE k BETWEEN 1 AND 12 GROUP BY 1, 2
),
med AS (SELECT APPROX_QUANTILES(vc_rate, 2)[OFFSET(1)] AS mv FROM wkr),
wf AS (
  SELECT wkr.k, wkr.week_start, wkr.vc_rate >= 0.8 * med.mv AS clean FROM wkr CROSS JOIN med
),
info AS (
  SELECT COUNT(*) AS n_all, COUNTIF(clean) AS n_cart,
    IFNULL(STRING_AGG(IF(clean, NULL, FORMAT_DATE('%F', DATE_ADD(week_start, INTERVAL 6 DAY))), ', ' ORDER BY week_start), '') AS excluded
  FROM wf
),
mm AS (
  SELECT m.*, IFNULL(wf.clean, FALSE) AS clean FROM m LEFT JOIN wf ON wf.k = m.k
),
agg AS (
  SELECT channel,
    SUM(IF(k = 0, s, 0)) AS s_t, SUM(IF(k BETWEEN 1 AND 12, s, 0)) AS s_b,
    SUM(IF(k = 0, ws_, 0)) AS ws_t, SUM(IF(k BETWEEN 1 AND 12, ws_, 0)) AS ws_b, SUM(IF(clean, ws_, 0)) AS ws_c,
    SUM(IF(k = 0, atc, 0)) AS atc_t, SUM(IF(k BETWEEN 1 AND 12, atc, 0)) AS atc_b,
    SUM(IF(k = 0, bnc, 0)) AS bnc_t, SUM(IF(k BETWEEN 1 AND 12, bnc, 0)) AS bnc_b,
    SUM(IF(k = 0, vc, 0)) AS vc_t, SUM(IF(k BETWEEN 1 AND 12, vc, 0)) AS vc_b, SUM(IF(clean, vc, 0)) AS vc_c,
    SUM(IF(k = 0, vco, 0)) AS vco_t, SUM(IF(k BETWEEN 1 AND 12, vco, 0)) AS vco_b, SUM(IF(clean, vco, 0)) AS vco_c,
    SUM(IF(k = 0, vcc, 0)) AS vcc_t, SUM(IF(k BETWEEN 1 AND 12, vcc, 0)) AS vcc_b, SUM(IF(clean, vcc, 0)) AS vcc_c,
    SUM(IF(k = 0, vct, 0)) AS vct_t, SUM(IF(k BETWEEN 1 AND 12, vct, 0)) AS vct_b
  FROM mm GROUP BY 1
),
u AS (
  SELECT * FROM agg
  UNION ALL
  SELECT 'Total', SUM(s_t), SUM(s_b), SUM(ws_t), SUM(ws_b), SUM(ws_c), SUM(atc_t), SUM(atc_b), SUM(bnc_t), SUM(bnc_b),
    SUM(vc_t), SUM(vc_b), SUM(vc_c), SUM(vco_t), SUM(vco_b), SUM(vco_c), SUM(vcc_t), SUM(vcc_b), SUM(vcc_c), SUM(vct_t), SUM(vct_b)
  FROM agg
),
tt AS (SELECT s_t, s_b FROM u WHERE channel = 'Total'),
x AS (
  SELECT u.channel,
    u.channel = 'Mobile App' AS app,
    SAFE_DIVIDE(vc_t, ws_t) AS vc_r, SAFE_DIVIDE(vc_c, ws_c) AS vc_rc, SAFE_DIVIDE(vc_b, ws_b) AS vc_rb,
    SAFE_DIVIDE(vco_t, vc_t) AS c2c, SAFE_DIVIDE(vco_c, vc_c) AS c2c_c, SAFE_DIVIDE(vco_b, vc_b) AS c2c_b,
    SAFE_DIVIDE(vcc_t, vc_t) AS c2cs, SAFE_DIVIDE(vcc_c, vc_c) AS c2cs_c, SAFE_DIVIDE(vcc_b, vc_b) AS c2cs_b,
    SAFE_DIVIDE(vct_t, vco_t) AS c2t, SAFE_DIVIDE(vct_b, vco_b) AS c2t_b,
    SAFE_DIVIDE(bnc_t, ws_t) AS bn, SAFE_DIVIDE(bnc_b, ws_b) AS bn_b,
    SAFE_DIVIDE(atc_t, ws_t) AS atr, SAFE_DIVIDE(atc_b, ws_b) AS atr_b,
    SAFE_DIVIDE(u.s_t, tt.s_t) AS mix, SAFE_DIVIDE(u.s_b, tt.s_b) AS mix_b,
    u.s_t, u.ws_t
  FROM u CROSS JOIN tt
)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  x.channel,
  CASE x.channel WHEN 'SEM' THEN 1 WHEN 'Mobile App' THEN 2 WHEN 'Social' THEN 3 WHEN 'SEO' THEN 4
    WHEN 'Email' THEN 5 WHEN 'Direct' THEN 6 WHEN 'SMS' THEN 7 WHEN 'Other' THEN 8 ELSE 9 END AS sort,
  x.s_t AS sessions,
  IF(x.app, NULL, x.ws_t) AS web_sessions,
  IF(x.app, NULL, ROUND(100 * x.vc_r, 4)) AS visited_cart,
  IF(x.app, NULL, ROUND(100 * (x.vc_r - x.vc_rc), 4)) AS visited_cart_pp,
  IF(x.app, NULL, ROUND(100 * x.c2c, 4)) AS cart_to_checkout,
  IF(x.app, NULL, ROUND(100 * (x.c2c - x.c2c_c), 4)) AS cart_to_checkout_pp,
  IF(x.app, NULL, ROUND(100 * x.c2cs, 4)) AS cart_to_checkout_strict,
  IF(x.app, NULL, ROUND(100 * (x.c2cs - x.c2cs_c), 4)) AS cart_to_checkout_strict_pp,
  IF(x.app, NULL, ROUND(100 * x.c2t, 4)) AS checkout_to_thanks,
  IF(x.app, NULL, ROUND(100 * (x.c2t - x.c2t_b), 4)) AS checkout_to_thanks_pp,
  IF(x.app, NULL, ROUND(100 * x.c2cs * x.c2t, 4)) AS cart_to_thanks,
  IF(x.app, NULL, ROUND(100 * (x.c2cs * x.c2t - x.c2cs_c * x.c2t_b), 4)) AS cart_to_thanks_pp,
  IF(x.app, NULL, ROUND(100 * x.bn, 4)) AS bounce,
  IF(x.app, NULL, ROUND(100 * (x.bn - x.bn_b), 4)) AS bounce_pp,
  IF(x.app, NULL, ROUND(100 * x.atr, 4)) AS add_to_cart,
  IF(x.app, NULL, ROUND(100 * (x.atr - x.atr_b), 4)) AS add_to_cart_pp,
  ROUND(100 * x.mix, 4) AS session_mix,
  ROUND(100 * (x.mix - x.mix_b), 4) AS session_mix_pp,
  info.n_cart AS cart_base_weeks,
  info.n_all AS base_weeks,
  info.excluded AS cart_base_excluded_weeks,
  IF(x.app, NULL, ROUND(100 * (x.vc_r - x.vc_rb), 4)) AS visited_cart_pp_all_weeks,
  IF(x.app, NULL, ROUND(100 * (x.c2c - x.c2c_b), 4)) AS cart_to_checkout_pp_all_weeks,
  IF(x.app, NULL, ROUND(100 * (x.c2cs * x.c2t - x.c2cs_b * x.c2t_b), 4)) AS cart_to_thanks_pp_all_weeks
FROM x CROSS JOIN info CROSS JOIN r
ORDER BY sort
