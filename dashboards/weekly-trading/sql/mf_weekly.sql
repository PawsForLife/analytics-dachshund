-- Dataset: mf_weekly
-- Title: Sessions 13-week trend
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Thirteen weekly rows ending with the reporting week, giving all-business-line sessions, visitors and page views plus Pet Circle sessions, orders and CVR for the trend chart. Reads online__session, reference__calendar_4_4_5_week. Sessions are Pet Circle only (business_line = 'Pet Circle').

WITH r AS (
  SELECT week_start_date AS ws, week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
wk AS (
  SELECT c.week_start_date, c.week_end_date, DATE_DIFF(r.ws, c.week_start_date, DAY) / 7 AS k
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` c CROSS JOIN r
  WHERE c.week_start_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.ws
),
mj AS (
  SELECT wk.week_start_date AS week_start, SUM(m.session_count) AS s, SUM(m.session_count_has_converted) AS o
  FROM `petcircle-warehouse-cloud.business_layer.online__session` m
  JOIN wk ON m.session_start_date BETWEEN wk.week_start_date AND wk.week_end_date
  WHERE m.bot_likelihood_category = 'Likely Human' AND m.business_line = 'Pet Circle'
    AND m.session_start_date BETWEEN (SELECT DATE_SUB(ws, INTERVAL 84 DAY) FROM r) AND (SELECT we FROM r)
  GROUP BY 1
),
os AS (
  SELECT wk.week_start_date,
    SUM(s.session_count_all) AS s_all,
    SUM(IF(s.digital_platform_type = 'Mobile App', s.session_count_all, 0)) AS s_app,
    SUM(IF(s.digital_platform_type = 'Mobile App', 0, s.session_count_all)) AS s_web,
    COUNT(DISTINCT s.user_device_id) AS uv,
    SUM(s.page_view_count_all) AS pv
  FROM `petcircle-warehouse-cloud.business_layer.online__session` s
  JOIN wk ON s.session_start_date BETWEEN wk.week_start_date AND wk.week_end_date
  WHERE s.bot_likelihood_category = 'Likely Human' AND s.business_line = 'Pet Circle'
    AND s.session_start_date BETWEEN (SELECT DATE_SUB(ws, INTERVAL 84 DAY) FROM r) AND (SELECT we FROM r)
  GROUP BY 1
)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  FORMAT_DATE('%F', r.we) AS report_week_end,
  FORMAT_DATE('%F', wk.week_end_date) AS week_end_row,
  CONCAT(CAST(EXTRACT(DAY FROM wk.week_end_date) AS STRING), FORMAT_DATE(' %b', wk.week_end_date)) AS wk_label,
  CAST(12 - wk.k AS INT64) AS sort,
  wk.k = 0 AS is_report_week,
  os.s_all AS sessions,
  os.s_web AS web_sessions,
  os.s_app AS app_sessions,
  os.uv AS unique_visitors,
  os.pv AS page_views,
  mj.s AS cube_sessions,
  mj.o AS orders,
  ROUND(100 * SAFE_DIVIDE(mj.o, mj.s), 4) AS cvr
FROM wk CROSS JOIN r
LEFT JOIN os ON os.week_start_date = wk.week_start_date
LEFT JOIN mj ON mj.week_start = wk.week_start_date
ORDER BY wk.week_end_date
