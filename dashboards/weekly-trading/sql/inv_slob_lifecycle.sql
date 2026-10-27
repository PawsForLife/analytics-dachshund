-- Dataset: inv_slob_lifecycle
-- Title: SLOB by lifecycle stage
-- Tab: Inventory
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: SLOB on a 12-week sell-rate basis by lifecycle stage (Released for Sale, Introduction, Exit) and book, as a share of the book's stock, with the stage's weeks cover. Reads inventory__item_trading_report, inventory__customer_order__item_warehouse, reference__calendar_4_4_5_week.

WITH cw AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
), itr AS (
  SELECT item_code, warehouse_name, category_description AS c,
    CASE WHEN lifecycle_stage IN ('Discontinued', 'Phasing Out', 'Write Off') THEN 'Exit' ELSE lifecycle_stage END AS stage,
    GREATEST(end_of_week_net_stock_quantity, 0) AS q,
    GREATEST(end_of_week_net_stock_quantity, 0) * cost_forecast AS sv,
    cost_forecast AS cf
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.inventory__item_trading_report`
  WHERE valid_for_date = (SELECT DATE_ADD(we, INTERVAL 1 DAY) FROM cw)
), bk AS (
  SELECT item_code, ANY_VALUE(CASE
    WHEN c IN ('Food', 'Treats', 'Chilled', 'Litter', 'Better Bundle') THEN 'Core Consumables'
    WHEN c IN ('Flea and Worming', 'Health', 'Grooming', 'Bird', 'Horse', 'Small Animal', 'Fish', 'Reptile') THEN 'Health & Other Species'
    WHEN c IN ('Toys', 'Training and Clean Up', 'Housing and Bedding', 'Smart Pet Products', 'Apparel and Accessories', 'Car and Travel Accessories', 'Feeding and Watering') THEN 'Hardlines'
    ELSE 'Unmapped' END) AS book
  FROM itr GROUP BY item_code
), s AS (
  SELECT item_code, warehouse_name, SUM(item_quantity) AS u12
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.inventory__customer_order__item_warehouse`
  WHERE calendar_date BETWEEN (SELECT DATE_SUB(we, INTERVAL 83 DAY) FROM cw) AND (SELECT we FROM cw)
  GROUP BY 1, 2
), j AS (
  SELECT b.book, i.stage, i.sv, IFNULL(s.u12, 0) * IFNULL(i.cf, 0) AS cogs12,
    i.q > 0 AND (IFNULL(s.u12, 0) <= 0 OR i.q * 84 / s.u12 > 285) AS is_slob
  FROM itr i JOIN bk b USING (item_code) LEFT JOIN s USING (item_code, warehouse_name)
), bt AS (
  SELECT book, SUM(sv) AS book_stk FROM j GROUP BY book
), a AS (
  SELECT book, stage, SUM(IF(is_slob, sv, 0)) AS slob, SUM(sv) AS stage_stk, SUM(cogs12) / 12 AS wk_cogs
  FROM j WHERE stage IN ('Released for Sale', 'Introduction', 'Exit') GROUP BY book, stage
)
SELECT
  IF(a.stage = 'Exit', 'Exit (Disc / Phasing / Write-off)', a.stage) AS stage,
  CASE a.stage WHEN 'Released for Sale' THEN 1 WHEN 'Introduction' THEN 2 ELSE 3 END AS stage_sort,
  a.book,
  CASE a.book WHEN 'Core Consumables' THEN 1 WHEN 'Health & Other Species' THEN 2 WHEN 'Hardlines' THEN 3 ELSE 4 END AS book_sort,
  ROUND(a.slob, 2) AS slob,
  ROUND(SAFE_DIVIDE(a.slob, bt.book_stk), 4) AS pct_book_stock,
  ROUND(a.stage_stk, 2) AS stage_stock,
  ROUND(SAFE_DIVIDE(a.stage_stk, a.wk_cogs), 1) AS wks_cover,
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw)) AS week_end
FROM a JOIN bt USING (book)
WHERE a.stage_stk <> 0 OR a.book <> 'Unmapped'
ORDER BY stage_sort, book_sort
