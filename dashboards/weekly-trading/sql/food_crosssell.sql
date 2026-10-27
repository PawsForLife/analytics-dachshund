-- Dataset: food_crosssell
-- Title: Food basket cross-sell
-- Tab: Commercial
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Share of this week's food orders that also hold a non-food line in each of the six core category groups. Reads product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT week_start_date AS ws, week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week
),
ord AS (
  SELECT o.order_id, o.customer_id, o.order_created_date AS d, o.order_origin AS origin, o.is_auto_delivery_order AS ad, o.is_first_customer_order_complete AS fst,
    o.product_revenue_complete_excl_gst AS rev, o.product_margin_complete_excl_gst AS pm
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  WHERE o.status != 'Cancelled' AND o.order_created_date BETWEEN (SELECT ws FROM cal) AND (SELECT we FROM cal)
),
bl AS (
  SELECT order_id, is_food, category_group_description AS grp
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date BETWEEN (SELECT ws FROM cal) AND (SELECT we FROM cal)
),
fo AS (
  SELECT DISTINCT b.order_id FROM bl b JOIN ord o USING (order_id) WHERE b.is_food
),
grp AS (
  SELECT * FROM UNNEST([
    STRUCT('Food and Treats' AS src, 'Food & Treats' AS category),
    STRUCT('Health and Wellness', 'Health & Wellness'),
    STRUCT('Litter', 'Litter'),
    STRUCT('Other Species', 'Other Species'),
    STRUCT('Accessories', 'Accessories'),
    STRUCT('Home and Living', 'Home & Living')
  ])
),
att AS (
  SELECT g.category, COUNT(DISTINCT x.order_id) AS orders
  FROM grp g LEFT JOIN (SELECT b.order_id, b.grp FROM bl b JOIN fo USING (order_id) WHERE NOT IFNULL(b.is_food, FALSE)) x ON x.grp = g.src
  GROUP BY 1
)
SELECT FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end, category,
  ROW_NUMBER() OVER (ORDER BY orders DESC, category) AS sort,
  ROUND(100 * orders / (SELECT COUNT(*) FROM fo), 4) AS pct_of_food_orders
FROM att ORDER BY sort
