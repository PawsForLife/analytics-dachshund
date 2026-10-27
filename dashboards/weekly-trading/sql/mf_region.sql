-- Dataset: mf_region
-- Title: Sessions by region
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Reporting-week sessions, mix, orders and conversion by visitor region, with a reconciliation flag against the channel total. Reads online__session, reference__calendar_4_4_5_week.

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
    CASE j.geo_region_group
      WHEN 'New South Wales' THEN 'NSW' WHEN 'Victoria' THEN 'VIC' WHEN 'Queensland' THEN 'QLD'
      WHEN 'Western Australia' THEN 'WA' WHEN 'South Australia' THEN 'SA' ELSE 'OTHER'
    END AS region,
    j.session_count AS s,
    j.session_count_has_converted AS o
  FROM `petcircle-warehouse-cloud.business_layer.online__session` j
  JOIN wk ON j.session_start_date BETWEEN wk.week_start_date AND wk.week_end_date
  WHERE j.bot_likelihood_category = 'Likely Human' AND j.business_line = 'Pet Circle'
    AND j.session_start_date BETWEEN (SELECT DATE_SUB(ws, INTERVAL 84 DAY) FROM r) AND (SELECT we FROM r)
),
nb AS (SELECT COUNT(DISTINCT k) AS n FROM m WHERE k BETWEEN 1 AND 12),
a AS (
  SELECT region,
    SUM(IF(k = 0, s, 0)) AS s_t, SUM(IF(k BETWEEN 1 AND 12, s, 0)) AS s_b,
    SUM(IF(k = 0, o, 0)) AS o_t, SUM(IF(k BETWEEN 1 AND 12, o, 0)) AS o_b
  FROM m GROUP BY 1
),
ch AS (
  SELECT SUM(j.session_count) AS s, SUM(j.session_count_has_converted) AS o
  FROM `petcircle-warehouse-cloud.business_layer.online__session` j CROSS JOIN r
  WHERE j.bot_likelihood_category = 'Likely Human' AND j.business_line = 'Pet Circle'
    AND j.session_start_date BETWEEN r.ws AND r.we
),
t AS (SELECT SUM(s_t) AS s_t, SUM(o_t) AS o_t, COUNTIF(region IN ('OTHER', 'UNKNOWN') AND s_t > 0) AS n_other, COUNTIF(s_t > 0) AS n_reg FROM a)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  a.region,
  CAST(ROW_NUMBER() OVER (ORDER BY IF(a.region IN ('OTHER', 'UNKNOWN'), 1, 0), a.s_t DESC, a.region) AS INT64) AS sort,
  a.s_t AS sessions,
  ROUND(100 * SAFE_DIVIDE(a.s_t, t.s_t), 4) AS mix,
  a.o_t AS orders,
  ROUND(100 * SAFE_DIVIDE(a.o_t, a.s_t), 4) AS cvr,
  ROUND(SAFE_DIVIDE(a.s_t, a.s_b / nb.n) - 1, 4) AS sessions_vs_l12w_pct,
  ROUND(100 * (SAFE_DIVIDE(a.o_t, a.s_t) - SAFE_DIVIDE(a.o_b, a.s_b)), 4) AS cvr_pp,
  t.s_t AS region_total_sessions,
  ch.s AS channel_total_sessions,
  t.s_t = ch.s AND t.o_t = ch.o AND t.n_reg > t.n_other AS reconciles
FROM a CROSS JOIN t CROSS JOIN ch CROSS JOIN nb CROSS JOIN r
WHERE a.s_t > 0
ORDER BY sort
