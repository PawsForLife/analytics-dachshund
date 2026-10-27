-- Dataset: ad_cancel
-- Title: AD cancellation flow
-- Tab: Auto Delivery
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Subscription lines cancelled, the active line base, the line cancellation rate and group cancellation counts (any line vs full exit) this week vs the LY week. Reads product__auto_delivery_group__eod, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

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
, m AS (
  SELECT
    MAX(IF(pk = 'tw', e, NULL)) AS e,
    MAX(IF(pk = 'tw', lines_cancelled, NULL)) AS lc_tw, MAX(IF(pk = 'ly', lines_cancelled, NULL)) AS lc_ly,
    MAX(IF(pk = 'tw', active_lines, NULL)) AS al_tw, MAX(IF(pk = 'ly', active_lines, NULL)) AS al_ly,
    MAX(IF(pk = 'tw', grp_cancel_any, NULL)) AS ga_tw, MAX(IF(pk = 'ly', grp_cancel_any, NULL)) AS ga_ly,
    MAX(IF(pk = 'tw', cancelled, NULL)) AS fe_tw, MAX(IF(pk = 'ly', cancelled, NULL)) AS fe_ly
  FROM f
),
r AS (
  SELECT e, 1 AS sort, 'Subscription lines cancelled' AS measure, 'n' AS unit, CAST(lc_tw AS FLOAT64) AS tw, CAST(lc_ly AS FLOAT64) AS ly FROM m
  UNION ALL SELECT e, 2, 'Active line base (Sunday snapshot)', 'n', al_tw, al_ly FROM m
  UNION ALL SELECT e, 3, 'Cancellation rate on active lines', 'pct', ROUND(SAFE_DIVIDE(lc_tw, al_tw) * 100, 4), ROUND(SAFE_DIVIDE(lc_ly, al_ly) * 100, 4) FROM m
  UNION ALL SELECT e, 4, 'Groups cancelling at least 1 line', 'n', ga_tw, ga_ly FROM m
  UNION ALL SELECT e, 5, 'Groups fully exiting (state to Cancelled)', 'n', fe_tw, fe_ly FROM m
  UNION ALL SELECT e, 6, 'Full-exit share of cancelling groups', 'pct', ROUND(SAFE_DIVIDE(fe_tw, ga_tw) * 100, 4), ROUND(SAFE_DIVIDE(fe_ly, ga_ly) * 100, 4) FROM m
)
SELECT sort, measure, unit, tw, ly,
  IF(unit = 'pct', ROUND((tw - ly) * 100, 2), NULL) AS yoy,
  CAST(e AS STRING) AS week_end
FROM r ORDER BY sort
