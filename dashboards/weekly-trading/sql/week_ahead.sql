-- Dataset: week_ahead
-- Title: Week ahead targets
-- Tab: Highlights
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Next calendar week's budget revenue and orders against this week's actual, plus the plan for the period the meeting opens next (next month if the reporting week closes a month, otherwise the rest of the current month). Reads product__customer_order, customer__forecast_customer_by_day, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (
  SELECT week_start_date AS rws, week_end_date AS rwe, merch_cal_month_name AS cmn,
    merch_cal_month_start_date AS cms, merch_cal_month_end_date AS cme
  FROM cal WHERE is_latest_merch_complete_week = TRUE
),
nx AS (
  SELECT c.week_start_date AS nws, c.week_end_date AS nwe,
    CONCAT(c.merch_cal_year_name, ' W', CAST(c.merch_cal_week_number_of_year AS STRING)) AS nfw,
    c.merch_cal_month_name AS nmn, c.merch_cal_month_start_date AS nms, c.merch_cal_month_end_date AS nme
  FROM cal c JOIN r ON c.week_start_date = DATE_ADD(r.rwe, INTERVAL 1 DAY)
),
f AS (
  SELECT calendar_date AS d, daily_forecast_gross_product_revenue AS rev, daily_forecast_order_count AS ord
  FROM `petcircle-warehouse-cloud.business_layer.customer__forecast_customer_by_day`
  WHERE calendar_date BETWEEN (SELECT cms FROM r) AND (SELECT nme FROM nx)
),
tw AS (
  SELECT SUM(o.product_revenue_complete_excl_gst) AS rev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o CROSS JOIN r
  WHERE o.status != 'Cancelled' AND o.order_created_date BETWEEN r.rws AND r.rwe
),
x AS (
  SELECT
    nx.nfw, nx.nwe, nx.nmn, r.cmn,
    nx.nms > r.cme AS new_month,
    (SELECT SUM(rev) FROM f WHERE d BETWEEN nx.nws AND nx.nwe) AS nb_rev,
    (SELECT SUM(ord) FROM f WHERE d BETWEEN nx.nws AND nx.nwe) AS nb_ord,
    (SELECT SUM(rev) FROM f WHERE d BETWEEN nx.nms AND nx.nme) AS nm_bud,
    (SELECT COUNT(*) FROM cal c WHERE c.week_end_date BETWEEN nx.nms AND nx.nme) AS nm_weeks,
    (SELECT IFNULL(SUM(rev), 0) FROM f WHERE d > r.rwe AND d <= r.cme) AS cur_rem,
    (SELECT COUNT(*) FROM cal c WHERE c.week_end_date > r.rwe AND c.week_end_date <= r.cme) AS cur_left,
    tw.rev AS tw_rev,
    r.rwe
  FROM r CROSS JOIN nx CROSS JOIN tw
)
SELECT
  nfw AS next_fy_wk,
  FORMAT_DATE('%F', nwe) AS next_week_end,
  ROUND(nb_rev, 2) AS next_budget_revenue,
  ROUND(nb_ord, 2) AS next_budget_orders,
  ROUND(SAFE_DIVIDE(nb_rev, tw_rev) - 1, 4) AS next_vs_tw_pct,
  IF(new_month, nmn, cmn) AS next_month_name,
  ROUND(IF(new_month, nm_bud, cur_rem), 2) AS next_month_budget,
  IF(new_month, nm_weeks, cur_left) AS next_month_weeks,
  new_month AS next_week_in_new_month,
  cmn AS cur_month_name,
  cur_left AS cur_weeks_left,
  ROUND(cur_rem, 2) AS cur_month_remaining_budget,
  FORMAT_DATE('%F', rwe) AS week_end
FROM x
