-- Dataset: inv_oos_matrix
-- Title: OOS % by book x warehouse
-- Tab: Inventory
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: SKU-availability OOS % for each book at each fulfilment warehouse, with book totals, warehouse totals and the national total. Reads inventory__inventory_holding_status__eod, inventory__warehouse, inventory__item_trading_report, reference__calendar_4_4_5_week.

WITH cw AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
), wh AS (
  SELECT warehouse_name, warehouse_state
  FROM `petcircle-warehouse-cloud.business_layer.inventory__warehouse`
  WHERE is_fulfilment_warehouse = TRUE
), bk AS (
  SELECT item_code, ANY_VALUE(CASE
    WHEN category_description IN ('Food', 'Treats', 'Chilled', 'Litter', 'Better Bundle') THEN 'Core Consumables'
    WHEN category_description IN ('Flea and Worming', 'Health', 'Grooming', 'Bird', 'Horse', 'Small Animal', 'Fish', 'Reptile') THEN 'Health & Other Species'
    WHEN category_description IN ('Toys', 'Training and Clean Up', 'Housing and Bedding', 'Smart Pet Products', 'Apparel and Accessories', 'Car and Travel Accessories', 'Feeding and Watering') THEN 'Hardlines'
    ELSE 'Unmapped' END) AS book
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.inventory__item_trading_report`
  WHERE valid_for_date = (SELECT DATE_ADD(we, INTERVAL 1 DAY) FROM cw)
  GROUP BY item_code
), h AS (
  SELECT COALESCE(b.book, 'Unmapped') AS bb, wh.warehouse_state AS ws, NOT h.has_stock AS is_oos
  FROM `petcircle-warehouse-cloud.business_layer.inventory__inventory_holding_status__eod` h
  JOIN wh USING (warehouse_name)
  LEFT JOIN bk b USING (item_code)
  WHERE h.valid_for_date = (SELECT we FROM cw) AND h.is_active_for_ordering_item
), a AS (
  SELECT COALESCE(bb, 'Total') AS bkk, COALESCE(ws, 'Total') AS wst, COUNT(*) AS active_items, COUNTIF(is_oos) AS oos_items
  FROM h GROUP BY CUBE(bb, ws)
)
SELECT
  bkk AS book,
  CASE bkk WHEN 'Core Consumables' THEN 1 WHEN 'Health & Other Species' THEN 2 WHEN 'Hardlines' THEN 3 WHEN 'Unmapped' THEN 4 ELSE 9 END AS book_sort,
  wst AS warehouse,
  CASE wst WHEN 'NSW' THEN 1 WHEN 'QLD' THEN 2 WHEN 'VIC' THEN 3 WHEN 'WA' THEN 4 WHEN 'Total' THEN 9 ELSE 5 END AS wh_sort,
  active_items,
  oos_items,
  ROUND(SAFE_DIVIDE(oos_items, active_items), 4) AS oos_pct,
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw)) AS week_end
FROM a
ORDER BY book_sort, wh_sort
