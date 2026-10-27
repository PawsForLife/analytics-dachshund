-- Dataset: fy_periods
-- Title: FY months and YTD
-- Tab: Highlights
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Completed 445 months of the FY, the current month to date (traded weeks) with its full-month budget, and FY YTD, actual revenue vs budget. Reads product__customer_order, customer__forecast_customer_by_day, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (
  SELECT week_end_date AS rwe, merch_cal_year_name AS fy, merch_cal_month_number AS rmn,
    merch_cal_month_start_date AS rms, merch_cal_month_end_date AS rme
  FROM cal WHERE is_latest_merch_complete_week = TRUE
),
wk AS (
  SELECT c.week_start_date AS ws, c.week_end_date AS we, c.merch_cal_week_number_of_year AS wn,
    c.merch_cal_year_name AS fy, c.merch_cal_month_name AS mname, c.merch_cal_month_number AS mnum,
    c.merch_cal_quarter_name AS qname, c.merch_cal_month_start_date AS ms, c.merch_cal_month_end_date AS me,
    c.week_end_date <= r.rwe AS is_actual, c.merch_cal_month_number = r.rmn AS in_cur
  FROM cal c CROSS JOIN r
  WHERE c.merch_cal_year_name = r.fy AND c.week_end_date <= r.rme
),
act AS (
  SELECT w.we, SUM(o.product_revenue_complete_excl_gst) AS actual
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled' AND w.is_actual
    AND o.order_created_date BETWEEN (SELECT MIN(ws) FROM wk) AND (SELECT rwe FROM r)
  GROUP BY w.we
),
bud AS (
  SELECT w.we, SUM(f.daily_forecast_gross_product_revenue) AS budget
  FROM `petcircle-warehouse-cloud.business_layer.customer__forecast_customer_by_day` f
  JOIN wk w ON f.calendar_date BETWEEN w.ws AND w.we
  GROUP BY w.we
),
fw AS (
  SELECT w.*, act.actual, bud.budget
  FROM wk w LEFT JOIN act USING (we) LEFT JOIN bud USING (we)
)
,
p AS (
  SELECT mnum AS sort, mname AS period, 'month' AS kind,
    COUNT(*) AS weeks_traded, COUNT(*) AS weeks_total,
    SUM(actual) AS actual, SUM(budget) AS budget, SUM(budget) AS full_budget, TRUE AS is_closed
  FROM fw CROSS JOIN r WHERE fw.me < r.rms GROUP BY mnum, mname
  UNION ALL
  SELECT ANY_VALUE(mnum), ANY_VALUE(mname), 'current',
    COUNTIF(is_actual), COUNT(*),
    SUM(IF(is_actual, actual, NULL)), SUM(IF(is_actual, budget, NULL)), SUM(budget),
    ANY_VALUE(r.rwe = r.rme)
  FROM fw CROSS JOIN r WHERE fw.in_cur
  UNION ALL
  SELECT 99, CONCAT(ANY_VALUE(fw.fy), ' YTD'), 'ytd',
    COUNTIF(is_actual), COUNTIF(is_actual),
    SUM(IF(is_actual, actual, NULL)), SUM(IF(is_actual, budget, NULL)), SUM(IF(is_actual, budget, NULL)),
    CAST(NULL AS BOOL)
  FROM fw CROSS JOIN r
)
SELECT sort, period, kind, weeks_traded, weeks_total,
  ROUND(actual, 2) AS actual, ROUND(budget, 2) AS budget,
  ROUND(actual - budget, 2) AS d_bud, ROUND(SAFE_DIVIDE(actual, budget) - 1, 4) AS d_bud_pct,
  ROUND(full_budget, 2) AS full_budget, is_closed,
  (SELECT FORMAT_DATE('%F', rwe) FROM r) AS week_end
FROM p
ORDER BY sort
