-- Dataset: inv_cover
-- Title: Stock by days of cover
-- Tab: Inventory
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Stock at cost, 6-week weekly sales, weeks cover and days of stock on hand by days-cover bucket, as at the reporting Sunday. Reads inventory__item_trading_report, reference__calendar_4_4_5_week.

WITH cw AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
), itr AS (
  SELECT
    GREATEST(end_of_week_net_stock_quantity, 0) AS q,
    GREATEST(end_of_week_net_stock_quantity, 0) * cost_forecast AS sv,
    cost_forecast AS cf,
    last_six_week_average_weekly_items_sold AS u6,
    last_six_week_average_weekly_sales AS r6
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.inventory__item_trading_report`
  WHERE valid_for_date = (SELECT DATE_ADD(we, INTERVAL 1 DAY) FROM cw)
), b AS (
  SELECT *,
    CASE WHEN q <= 0 THEN 1
      WHEN IFNULL(u6, 0) <= 0 THEN 5
      WHEN q / (u6 / 7) <= 50 THEN 1
      WHEN q / (u6 / 7) <= 90 THEN 2
      WHEN q / (u6 / 7) <= 150 THEN 3
      WHEN q / (u6 / 7) <= 285 THEN 4
      ELSE 5 END AS sort
  FROM itr
), a AS (
  SELECT sort, SUM(sv) AS stk, SUM(IFNULL(r6, 0)) AS r6, SUM(IFNULL(u6, 0) * IFNULL(cf, 0)) AS cogs6 FROM b GROUP BY sort
)
SELECT
  CASE sort WHEN 1 THEN '0-50d' WHEN 2 THEN '51-90d' WHEN 3 THEN '91-150d' WHEN 4 THEN '151-284d' ELSE '>285d / no sale' END AS bucket,
  sort,
  ROUND(stk, 2) AS stock_at_cost,
  ROUND(SAFE_DIVIDE(stk, SUM(stk) OVER ()), 4) AS stock_mix_pct,
  ROUND(r6, 2) AS wkly_sales_6wk,
  ROUND(SAFE_DIVIDE(r6, SUM(r6) OVER ()), 4) AS sales_mix_pct,
  ROUND(cogs6, 2) AS wkly_cogs_6wk,
  ROUND(SAFE_DIVIDE(stk, cogs6), 2) AS wks_cover,
  ROUND(SAFE_DIVIDE(stk, cogs6) * 7, 2) AS dsoh,
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw)) AS week_end
FROM a
ORDER BY sort
