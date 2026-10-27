-- Dataset: inv_cover_trend
-- Title: Days-cover mix, 6 weeks
-- Tab: Inventory
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Stock at cost by days-cover bucket for each of the last six Sundays, with the six-week change and mix change per bucket. Reads inventory__inventory_holding_status__eod, inventory__customer_order__item_warehouse, reference__calendar_4_4_5_week.

WITH cw AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
), wk AS (
  SELECT k, DATE_SUB(we, INTERVAL 7 * k DAY) AS d FROM cw, UNNEST(GENERATE_ARRAY(0, 5)) AS k
), h AS (
  SELECT valid_for_date AS d, item_code, warehouse_name, GREATEST(net_stock_quantity, 0) AS q, stock_value_cost_forecast AS sv
  FROM `petcircle-warehouse-cloud.business_layer.inventory__inventory_holding_status__eod`
  WHERE valid_for_date IN (SELECT d FROM wk) AND stock_value_cost_forecast <> 0
), s AS (
  SELECT wk.d, c.item_code, c.warehouse_name, SUM(c.item_quantity) / 6 AS u6
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.inventory__customer_order__item_warehouse` c
  JOIN wk ON c.calendar_date BETWEEN DATE_SUB(wk.d, INTERVAL 41 DAY) AND wk.d
  WHERE c.calendar_date BETWEEN (SELECT DATE_SUB(we, INTERVAL 76 DAY) FROM cw) AND (SELECT we FROM cw)
  GROUP BY 1, 2, 3
), j AS (
  SELECT h.d, h.sv,
    CASE WHEN h.q <= 0 THEN 1
      WHEN IFNULL(s.u6, 0) <= 0 THEN 5
      WHEN h.q / (s.u6 / 7) <= 50 THEN 1
      WHEN h.q / (s.u6 / 7) <= 90 THEN 2
      WHEN h.q / (s.u6 / 7) <= 150 THEN 3
      WHEN h.q / (s.u6 / 7) <= 285 THEN 4
      ELSE 5 END AS sort
  FROM h LEFT JOIN s USING (d, item_code, warehouse_name)
), g AS (
  SELECT b.d, b.k, b.sort, IFNULL(SUM(j.sv), 0) AS stk
  FROM (SELECT wk.d, wk.k, x AS sort FROM wk CROSS JOIN UNNEST([1, 2, 3, 4, 5]) AS x) b
  LEFT JOIN j ON j.d = b.d AND j.sort = b.sort
  GROUP BY 1, 2, 3
), gt AS (
  SELECT d, k, sort, stk FROM g
  UNION ALL
  SELECT d, k, 9, SUM(stk) FROM g GROUP BY d, k
), m AS (
  SELECT gt.*, SAFE_DIVIDE(stk, SUM(IF(sort = 9, 0, stk)) OVER (PARTITION BY d)) AS mix FROM gt
), c AS (
  SELECT m.*,
    MAX(IF(k = 0, stk, NULL)) OVER (PARTITION BY sort) - MAX(IF(k = 5, stk, NULL)) OVER (PARTITION BY sort) AS ch,
    MAX(IF(k = 0, mix, NULL)) OVER (PARTITION BY sort) - MAX(IF(k = 5, mix, NULL)) OVER (PARTITION BY sort) AS mch
  FROM m
)
SELECT
  FORMAT_DATE('%Y-%m-%d', d) AS week_end_row,
  CONCAT(CAST(EXTRACT(DAY FROM d) AS STRING), ' ', FORMAT_DATE('%b', d)) AS wk_label,
  CASE sort WHEN 1 THEN '0-50d' WHEN 2 THEN '51-90d' WHEN 3 THEN '91-150d' WHEN 4 THEN '151-284d' WHEN 5 THEN '>285d / no sale' ELSE 'Total stock at cost' END AS bucket,
  sort,
  ROUND(stk, 2) AS stock_at_cost,
  ROUND(mix, 4) AS mix_pct,
  ROUND(ch, 2) AS change_6w,
  IF(sort = 9, NULL, ROUND(100 * mch, 2)) AS mix_change_pp,
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw)) AS report_week_end,
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw)) AS week_end
FROM c
ORDER BY d, sort
