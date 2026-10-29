-- Dataset: inv_health
-- Title: Inventory health headline
-- Tab: Inventory
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Stock at cost, SLOB share vs the 20% guardrail, OOS lost sales (4-week average sales, Released for Sale and Introduction lines), supplier poor-fill and the 90-day fill rate as at the reporting Sunday. Reads inventory__item_trading_report, inventory__inventory_holding_status__eod, inventory__customer_order__item_warehouse, inventory__inventory_requisition_order, reference__calendar_4_4_5_week.

WITH cw AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
), itr AS (
  SELECT item_code, warehouse_name, lifecycle_stage AS ls,
    GREATEST(end_of_week_net_stock_quantity, 0) AS q,
    GREATEST(end_of_week_net_stock_quantity, 0) * cost_forecast AS sv,
    last_six_week_average_weekly_items_sold AS u6
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.inventory__item_trading_report`
  WHERE valid_for_date = (SELECT DATE_ADD(we, INTERVAL 1 DAY) FROM cw)
), cur AS (
  SELECT SUM(sv) AS stk, SUM(IF(q > 0 AND (IFNULL(u6, 0) <= 0 OR q / (u6 / 7) > 285), sv, 0)) AS slob FROM itr
), oh AS (
  SELECT item_code, warehouse_name
  FROM `petcircle-warehouse-cloud.business_layer.inventory__inventory_holding_status__eod`
  WHERE valid_for_date = (SELECT we FROM cw) AND count_item_out_of_stock > 0
), lc AS (
  SELECT item_code, warehouse_name, ANY_VALUE(ls) AS ls FROM itr GROUP BY 1, 2
), sl AS (
  SELECT item_code, warehouse_name, SUM(item_revenue) / 4 AS r4
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.inventory__customer_order__item_warehouse`
  WHERE calendar_date BETWEEN (SELECT DATE_SUB(we, INTERVAL 27 DAY) FROM cw) AND (SELECT we FROM cw)
  GROUP BY 1, 2
), fl AS (
  SELECT d.item_code, d.warehouse_name, SUM(LEAST(d.quantity_received, d.quantity_ordered)) AS rq, SUM(d.quantity_ordered) AS oq
  FROM `petcircle-warehouse-cloud.business_layer.inventory__inventory_requisition_order` o, UNNEST(o.inventory_requisition_order_detail) d
  WHERE o.inventory_requisition_order_stage <> 'Open'
    AND o.inventory_requisition_expected_delivered_date BETWEEN (SELECT DATE_SUB(we, INTERVAL 89 DAY) FROM cw) AND (SELECT we FROM cw)
  GROUP BY 1, 2
), oo AS (
  SELECT SUM(sl.r4) AS lost, SUM(IF(IFNULL(SAFE_DIVIDE(fl.rq, fl.oq) < 0.92, FALSE), sl.r4, 0)) AS pf
  FROM oh JOIN sl USING (item_code, warehouse_name) JOIN lc USING (item_code, warehouse_name) LEFT JOIN fl USING (item_code, warehouse_name)
  WHERE lc.ls IN ('Released for Sale', 'Introduction')
), ff AS (
  SELECT SAFE_DIVIDE(SUM(rq), SUM(oq)) AS fill FROM fl
)
SELECT
  ROUND(cur.stk, 2) AS stock_at_cost,
  ROUND(cur.slob, 2) AS slob,
  ROUND(SAFE_DIVIDE(cur.slob, cur.stk), 4) AS slob_pct,
  ROUND(oo.lost, 2) AS oos_lost_wk,
  ROUND(oo.pf, 2) AS poor_fill_lost,
  ROUND(SAFE_DIVIDE(oo.pf, oo.lost), 4) AS poor_fill_pct,
  ROUND(ff.fill, 4) AS fill_90d,
  0.2 AS slob_guardrail_pct,
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw)) AS as_at,
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw)) AS week_end
FROM cur, oo, ff
