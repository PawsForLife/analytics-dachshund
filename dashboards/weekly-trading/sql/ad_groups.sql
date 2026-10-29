-- Dataset: ad_groups
-- Title: AD group net movement
-- Tab: Auto Delivery
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Group-level movement of the active AD base over the week: inflows (activations and reactivations, groups entering Active) and outflows (cancellations, pauses and other exits, groups leaving Active), which tie exactly to the change in active groups (unreconciled is a check and should be 0); churn on the opening base; and a memo count of already-paused groups cancelled. Reads product__auto_delivery_group__eod, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH p AS (
  SELECT 'tw' AS pk, week_end_date AS e FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
  UNION ALL
  SELECT 'ly', week_end_date FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_prior_year_latest_merch_complete_week = TRUE
),
dd AS (SELECT pk, e, d FROM p, UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(e, INTERVAL 7 DAY), e)) AS d),
g AS (
  SELECT dd.pk, dd.e, x.valid_for_date AS d, x.auto_delivery_group_id AS gid, x.auto_delivery_group_state AS s
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
    COUNTIF(ps = 'Active' AND s = 'Cancelled') AS cancelled,
    COUNTIF(ps = 'Active' AND s = 'Paused') AS paused,
    COUNTIF(ps = 'Active' AND s NOT IN ('Active', 'Paused', 'Cancelled')) AS other_exits,
    COUNTIF(ps = 'Paused' AND s = 'Cancelled') AS paused_then_cancelled
  FROM t GROUP BY pk
)
SELECT
  opening, activated, reactivated, cancelled, paused, other_exits,
  activated + reactivated AS inflows,
  cancelled + paused + other_exits AS outflows,
  (activated + reactivated) - (cancelled + paused + other_exits) AS net_counted,
  (closing - opening) - ((activated + reactivated) - (cancelled + paused + other_exits)) AS unreconciled,
  closing,
  closing - opening AS net_change,
  paused_then_cancelled,
  ROUND(SAFE_DIVIDE(cancelled, opening) * 100, 4) AS churn_on_base,
  ROUND(SAFE_DIVIDE((closing - opening) - ((activated + reactivated) - (cancelled + paused + other_exits)), activated + reactivated + cancelled + paused + other_exits) * 100, 4) AS unreconciled_share_of_gross,
  CAST(e AS STRING) AS week_end
FROM f WHERE pk = 'tw'
