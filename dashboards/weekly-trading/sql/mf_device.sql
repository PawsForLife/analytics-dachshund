-- Dataset: mf_device
-- Title: Sessions by device
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Reporting-week sessions by device with change vs last week and share of all sessions, with app sessions identified by platform rather than device. Pet Circle only, likely-human sessions, so it reconciles to the traffic overview. Reads online__session, reference__calendar_4_4_5_week.

WITH r AS (
  SELECT week_start_date AS ws, week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
s AS (
  SELECT
    IF(o.session_start_date >= r.ws, 0, 1) AS k,
    CASE
      WHEN o.digital_platform_type = 'Mobile App' THEN 'Mobile App'
      WHEN o.device_category = 'mobile' THEN 'Mobile web'
      WHEN o.device_category = 'desktop' THEN 'Desktop'
      WHEN o.device_category = 'tablet' THEN 'Tablet'
      ELSE 'Other device'
    END AS device,
    o.session_count_all AS n
  FROM `petcircle-warehouse-cloud.business_layer.online__session` o CROSS JOIN r
  WHERE o.bot_likelihood_category = 'Likely Human'
    AND o.business_line = 'Pet Circle'
    AND o.session_start_date BETWEEN DATE_SUB(r.ws, INTERVAL 7 DAY) AND r.we
),
a AS (
  SELECT device, SUM(IF(k = 0, n, 0)) AS tw, SUM(IF(k = 1, n, 0)) AS lw FROM s GROUP BY 1
),
tot AS (SELECT SUM(tw) AS tw FROM a)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  a.device,
  CASE a.device WHEN 'Mobile web' THEN 1 WHEN 'Mobile App' THEN 2 WHEN 'Desktop' THEN 3 WHEN 'Tablet' THEN 4 ELSE 5 END AS sort,
  a.tw AS sessions,
  a.lw AS sessions_lw,
  ROUND(SAFE_DIVIDE(a.tw, a.lw) - 1, 4) AS vs_lw_pct,
  ROUND(100 * SAFE_DIVIDE(a.tw, tot.tw), 4) AS share
FROM a CROSS JOIN tot CROSS JOIN r
WHERE a.device != 'Other device'
ORDER BY sort
