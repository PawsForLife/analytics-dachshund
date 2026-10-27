-- Dataset: cal
-- Title: Reporting week calendar
-- Tab: Highlights
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: The reporting 445 week, its month, quarter, LY week, next week and plan label, resolved from the calendar. Reads reference__calendar_4_4_5_week.

WITH c AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT * FROM c WHERE is_latest_merch_complete_week = TRUE),
ly AS (SELECT * FROM c WHERE is_prior_year_latest_merch_complete_week = TRUE),
nx AS (SELECT c.* FROM c JOIN r ON c.week_start_date = DATE_ADD(r.week_end_date, INTERVAL 1 DAY))
SELECT
  FORMAT_DATE('%F', r.week_start_date) AS week_start,
  FORMAT_DATE('%F', r.week_end_date) AS week_end,
  r.merch_cal_year_name AS fy,
  r.merch_cal_week_number_of_year AS wk_of_year,
  CONCAT(r.merch_cal_year_name, ' W', CAST(r.merch_cal_week_number_of_year AS STRING)) AS fy_wk,
  r.merch_cal_quarter_name AS quarter_name,
  CAST(REGEXP_EXTRACT(r.merch_cal_quarter_name, r'(\d+)') AS INT64) AS quarter_num,
  r.merch_cal_month_name AS month_name,
  FORMAT_DATE('%F', r.merch_cal_month_start_date) AS month_start,
  FORMAT_DATE('%F', r.merch_cal_month_end_date) AS month_end,
  IF(r.merch_cal_quarter_name = 'Quarter 1', 'Budget', 'Forecast') AS plan_label,
  FORMAT_DATE('%F', ly.week_start_date) AS ly_week_start,
  FORMAT_DATE('%F', ly.week_end_date) AS ly_week_end,
  FORMAT_DATE('%F', DATE_SUB(r.week_end_date, INTERVAL 7 DAY)) AS lw_week_end,
  FORMAT_DATE('%F', nx.week_start_date) AS next_week_start,
  FORMAT_DATE('%F', nx.week_end_date) AS next_week_end,
  CONCAT(nx.merch_cal_year_name, ' W', CAST(nx.merch_cal_week_number_of_year AS STRING)) AS next_fy_wk,
  nx.merch_cal_month_name AS next_month_name,
  r.week_end_date = r.merch_cal_month_end_date AS is_month_close,
  CONCAT('Mon ', CAST(EXTRACT(DAY FROM r.week_start_date) AS STRING), FORMAT_DATE(' %b', r.week_start_date), ' - Sun ', CAST(EXTRACT(DAY FROM r.week_end_date) AS STRING), FORMAT_DATE(' %b %Y', r.week_end_date)) AS period_str
FROM r CROSS JOIN ly LEFT JOIN nx ON TRUE
