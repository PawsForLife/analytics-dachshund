-- Dataset: inv_oos_wh
-- Title: SKU availability by warehouse
-- Tab: Inventory
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Active-for-ordering items and how many are out of stock at each fulfilment warehouse and nationally at the reporting Sunday, with the warehouse OOS target where loaded and a data-quality caveat when a site's active count falls more than 30% in three weeks. Reads inventory__inventory_holding_status__eod, inventory__warehouse, inventory__targets_warehouse_by_day, reference__calendar_4_4_5_week.

WITH cw AS (
  SELECT week_end_date AS we, week_start_date AS ws FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
), wh AS (
  SELECT warehouse_name, warehouse_state, CONCAT(warehouse_state, ' ', REGEXP_REPLACE(warehouse_name, r'^[A-Z]+-WH ', '')) AS label
  FROM `petcircle-warehouse-cloud.business_layer.inventory__warehouse`
  WHERE is_fulfilment_warehouse = TRUE
), h AS (
  SELECT h.warehouse_name,
    COUNTIF(h.valid_for_date = (SELECT we FROM cw) AND h.is_active_for_ordering_item) AS active_items,
    COUNTIF(h.valid_for_date = (SELECT we FROM cw) AND h.is_active_for_ordering_item AND NOT h.has_stock) AS oos_items,
    COUNTIF(h.valid_for_date = (SELECT DATE_SUB(we, INTERVAL 21 DAY) FROM cw) AND h.is_active_for_ordering_item) AS active_3w
  FROM `petcircle-warehouse-cloud.business_layer.inventory__inventory_holding_status__eod` h
  JOIN wh USING (warehouse_name)
  WHERE h.valid_for_date IN ((SELECT we FROM cw), (SELECT DATE_SUB(we, INTERVAL 21 DAY) FROM cw))
  GROUP BY 1
), t AS (
  SELECT warehouse_name, AVG(daily_target_out_of_stock) AS tgt
  FROM `petcircle-warehouse-cloud.business_layer.inventory__targets_warehouse_by_day`
  WHERE calendar_date BETWEEN (SELECT ws FROM cw) AND (SELECT we FROM cw)
  GROUP BY 1
), w AS (
  SELECT wh.label AS warehouse, ROW_NUMBER() OVER (ORDER BY wh.warehouse_state, wh.warehouse_name) AS sort,
    h.active_items, h.oos_items, h.active_3w, t.tgt,
    SAFE_DIVIDE(h.active_items, h.active_3w) - 1 AS chg_3w
  FROM wh JOIN h USING (warehouse_name) LEFT JOIN t USING (warehouse_name)
), n AS (
  SELECT 'National' AS warehouse, 9 AS sort, SUM(active_items) AS active_items, SUM(oos_items) AS oos_items, SUM(active_3w) AS active_3w,
    (SELECT AVG(daily_target_out_of_stock) FROM `petcircle-warehouse-cloud.business_layer.inventory__targets_warehouse_by_day`
      WHERE warehouse_name = 'National' AND calendar_date BETWEEN (SELECT ws FROM cw) AND (SELECT we FROM cw)) AS tgt,
    SAFE_DIVIDE(SUM(active_items), SUM(active_3w)) - 1 AS chg_3w,
    STRING_AGG(IF(chg_3w < -0.3, warehouse, NULL), ', ') AS flagged
  FROM w
)
SELECT warehouse, sort, active_items, oos_items,
  ROUND(SAFE_DIVIDE(oos_items, active_items), 4) AS oos_pct,
  ROUND(tgt, 4) AS oos_target_pct,
  active_3w AS active_items_3w_ago,
  ROUND(chg_3w, 4) AS active_vs_3w_pct,
  IF(chg_3w < -0.3,
    CONCAT('Active-for-ordering count ', FORMAT('%d', active_items), ' vs ', FORMAT('%d', active_3w), ' three weeks earlier (', FORMAT('%.0f', 100 * chg_3w), '%) with no matching stock event: likely the upstream ranging-flag break. OOS % for this site is understated.'),
    NULL) AS caveat,
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw)) AS week_end
FROM w
UNION ALL
SELECT warehouse, sort, active_items, oos_items,
  ROUND(SAFE_DIVIDE(oos_items, active_items), 4),
  ROUND(tgt, 4),
  active_3w,
  ROUND(chg_3w, 4),
  IF(flagged IS NOT NULL, CONCAT('National OOS % understated: active-for-ordering count break at ', flagged, '.'), NULL),
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw))
FROM n
ORDER BY sort
