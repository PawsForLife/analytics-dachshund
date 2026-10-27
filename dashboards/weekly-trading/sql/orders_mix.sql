-- Dataset: orders_mix
-- Title: Orders and AOV mix
-- Tab: Commercial
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Reporting-week orders, revenue, AOV and shares by channel, customer status and delivery state, against last week and the 12-week prior average. Reads product__customer_order, customer__customer_order_basket, logistics__customer_order_delivery, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_end_date AS rwe FROM cal WHERE is_latest_merch_complete_week = TRUE),
wk AS (
  SELECT c.week_start_date AS ws, c.week_end_date AS we,
    c.week_end_date = r.rwe AS is_tw,
    c.week_end_date = DATE_SUB(r.rwe, INTERVAL 7 DAY) AS is_lw,
    c.week_end_date < r.rwe AS is_p12
  FROM cal c CROSS JOIN r
  WHERE c.week_end_date BETWEEN DATE_SUB(r.rwe, INTERVAL 84 DAY) AND r.rwe
),
rng AS (SELECT MIN(ws) AS d0, MAX(we) AS d1 FROM wk),
o AS (
  SELECT w.we, o.order_id, o.order_created_date AS od,
    ANY_VALUE(o.order_origin) AS origin,
    ANY_VALUE(o.is_first_customer_order_complete) AS is_new,
    ANY_VALUE(o.product_revenue_complete_excl_gst) AS rev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled'
    AND o.order_created_date BETWEEN (SELECT d0 FROM rng) AND (SELECT d1 FROM rng)
  GROUP BY w.we, o.order_id, o.order_created_date
),
bk AS (
  SELECT order_id, ANY_VALUE(date_of_previous_order) AS prev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date BETWEEN (SELECT d0 FROM rng) AND (SELECT d1 FROM rng)
  GROUP BY order_id
),
st AS (
  SELECT order_id, ANY_VALUE(customer_order_delivery_address.state) AS state
  FROM `petcircle-warehouse-cloud.business_layer.logistics__customer_order_delivery`
  WHERE order_created_date BETWEEN (SELECT d0 FROM rng) AND (SELECT d1 FROM rng)
  GROUP BY order_id
),
ob AS (
  SELECT o.we, o.order_id, o.rev,
    CASE WHEN o.origin = 'Schedule' THEN 'AD Scheduled' ELSE o.origin END AS channel,
    CASE WHEN o.is_new THEN 'New'
      WHEN bk.prev IS NULL OR DATE_DIFF(o.od, bk.prev, DAY) >= 92 THEN 'Reactivated'
      ELSE 'Returning' END AS cstatus,
    IFNULL(NULLIF(UPPER(TRIM(st.state)), ''), 'UNKNOWN') AS state
  FROM o LEFT JOIN bk USING (order_id) LEFT JOIN st USING (order_id)
),
lg AS (
  SELECT we, x.cut, x.value, COUNT(*) AS orders, SUM(rev) AS rev
  FROM ob,
  UNNEST([STRUCT('channel' AS cut, channel AS value), STRUCT('status', cstatus), STRUCT('state', state),
          STRUCT('channel', 'Total'), STRUCT('status', 'Total'), STRUCT('state', 'Total')]) x
  GROUP BY we, x.cut, x.value
),
vals AS (SELECT DISTINCT cut, value FROM lg),
dn AS (
  SELECT w.we, w.is_tw, w.is_lw, w.is_p12, v.cut, v.value,
    IFNULL(lg.orders, 0) AS orders, IFNULL(lg.rev, 0) AS rev
  FROM wk w CROSS JOIN vals v
  LEFT JOIN lg ON lg.we = w.we AND lg.cut = v.cut AND lg.value = v.value
),
sh AS (
  SELECT d.*,
    SAFE_DIVIDE(d.orders, t.orders) * 100 AS share,
    SAFE_DIVIDE(d.rev, t.rev) * 100 AS rshare,
    SAFE_DIVIDE(d.rev, NULLIF(d.orders, 0)) AS aov
  FROM dn d JOIN dn t ON t.we = d.we AND t.cut = d.cut AND t.value = 'Total'
),
so AS (
  SELECT cut, value, off + 1 AS srt FROM (
    SELECT 'channel' AS cut, ['Website', 'Mobile App', 'AD Scheduled', 'CX'] AS a UNION ALL
    SELECT 'status', ['New', 'Reactivated', 'Returning'] UNION ALL
    SELECT 'state', ['NSW', 'VIC', 'QLD', 'WA', 'SA', 'ACT', 'TAS', 'NT', 'UNKNOWN']
  ), UNNEST(a) AS value WITH OFFSET off
),
ag AS (
  SELECT cut, value,
    MAX(IF(is_tw, orders, NULL)) AS o_tw, MAX(IF(is_lw, orders, NULL)) AS o_lw, AVG(IF(is_p12, orders, NULL)) AS o_l13,
    MAX(IF(is_tw, share, NULL)) AS s_tw, MAX(IF(is_lw, share, NULL)) AS s_lw, AVG(IF(is_p12, share, NULL)) AS s_l13,
    MAX(IF(is_tw, rev, NULL)) AS r_tw,
    MAX(IF(is_tw, aov, NULL)) AS a_tw, MAX(IF(is_lw, aov, NULL)) AS a_lw, AVG(IF(is_p12, aov, NULL)) AS a_l13,
    MAX(IF(is_tw, rshare, NULL)) AS rs_tw, MAX(IF(is_lw, rshare, NULL)) AS rs_lw, AVG(IF(is_p12, rshare, NULL)) AS rs_l13
  FROM sh GROUP BY cut, value
)
SELECT
  cut, value,
  IF(value = 'Total', 99, IFNULL(so.srt, 90)) AS sort,
  o_tw AS orders_tw, o_lw AS orders_lw, ROUND(o_l13, 2) AS orders_l13w,
  ROUND(SAFE_DIVIDE(o_tw, o_lw) - 1, 4) AS orders_pct_lw,
  ROUND(SAFE_DIVIDE(o_tw, o_l13) - 1, 4) AS orders_pct_l13w,
  ROUND(s_tw, 4) AS share_tw, ROUND(s_tw - s_lw, 4) AS share_pp_lw, ROUND(s_tw - s_l13, 4) AS share_pp_l13w,
  ROUND(r_tw, 2) AS revenue_tw,
  ROUND(a_tw, 2) AS aov_tw,
  ROUND(SAFE_DIVIDE(a_tw, a_lw) - 1, 4) AS aov_pct_lw,
  ROUND(SAFE_DIVIDE(a_tw, a_l13) - 1, 4) AS aov_pct_l13w,
  ROUND(rs_tw, 4) AS rev_share_tw, ROUND(rs_tw - rs_lw, 4) AS rev_share_pp_lw, ROUND(rs_tw - rs_l13, 4) AS rev_share_pp_l13w,
  (SELECT FORMAT_DATE('%F', rwe) FROM r) AS week_end
FROM ag LEFT JOIN so USING (cut, value)
ORDER BY CASE cut WHEN 'channel' THEN 1 WHEN 'status' THEN 2 ELSE 3 END, sort, value
