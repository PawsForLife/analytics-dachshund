-- Dataset: ad_groups
-- Title: AD group net movement
-- Tab: Auto Delivery
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Group-level movement of the active AD base over the week (activations, reactivations, full cancellations, pauses) with the unreconciled gap to the actual change in active groups and churn on the opening base. Reads product__auto_delivery_group__eod, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH p AS (
  SELECT 'tw' AS pk, week_end_date AS e FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
  UNION ALL
  SELECT 'ly', week_end_date FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_prior_year_latest_merch_complete_week = TRUE
),
dd AS (SELECT pk, e, d FROM p, UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(e, INTERVAL 7 DAY), e)) AS d),
g AS (
  SELECT dd.pk, dd.e, x.valid_for_date AS d, x.auto_delivery_group_id AS gid, x.auto_delivery_group_state AS s,
    x.count_of_cancelled_auto_delivery_orders_today AS lc, x.has_cancelled_auto_delivery_orders_today AS hc,
    x.count_of_active_auto_delivery_orders AS al
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__auto_delivery_group__eod` WHERE EXISTS (SELECT 1 FROM UNNEST(auto_delivery_order) ad_l WHERE ad_l.store_id = 'pc-au')) x
  JOIN dd ON x.valid_for_date = dd.d
  WHERE x.valid_for_date IN (SELECT d FROM dd)
),
t AS (SELECT *, LAG(s) OVER (PARTITION BY pk, gid ORDER BY d) AS ps FROM g),
f AS (
  SELECT pk, ANY_VALUE(e) AS e,
    COUNTIF(d = DATE_SUB(e, INTERVAL 7 DAY) AND s = 'Active') AS opening,
    COUNTIF(d = e AND s = 'Active') AS closing,
    COUNTIF(d > DATE_SUB(e, INTERVAL 7 DAY) AND s = 'Active' AND (ps IS NULL OR ps NOT IN ('Active', 'Paused', 'Cancelled'))) AS activated,
    COUNTIF(s = 'Active' AND ps IN ('Paused', 'Cancelled')) AS reactivated,
    COUNTIF(s = 'Cancelled' AND ps IS NOT NULL AND ps != 'Cancelled') AS cancelled,
    COUNTIF(s = 'Paused' AND ps IS NOT NULL AND ps != 'Paused') AS paused,
    SUM(IF(d > DATE_SUB(e, INTERVAL 7 DAY), lc, 0)) AS lines_cancelled,
    COUNTIF(d > DATE_SUB(e, INTERVAL 7 DAY) AND hc) AS grp_cancel_any,
    SUM(IF(d = e, al, 0)) AS active_lines
  FROM t GROUP BY pk
)
SELECT
  opening, activated, reactivated, cancelled, paused,
  activated + reactivated AS inflows,
  cancelled + paused AS outflows,
  (activated + reactivated) - (cancelled + paused) AS net_counted,
  (closing - opening) - ((activated + reactivated) - (cancelled + paused)) AS unreconciled,
  closing,
  closing - opening AS net_change,
  ROUND(SAFE_DIVIDE(cancelled, opening) * 100, 4) AS churn_on_base,
  ROUND(SAFE_DIVIDE((closing - opening) - ((activated + reactivated) - (cancelled + paused)), activated + reactivated + cancelled + paused) * 100, 4) AS unreconciled_share_of_gross,
  CAST(e AS STRING) AS week_end
FROM f WHERE pk = 'tw'
