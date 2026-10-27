-- Dataset: mf_sem_category
-- Title: SEM by category
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Paid search (Google and Bing) spend, delivery, platform-reported ROAS and Google impression share by product category against the prior-12-week average. Reads marketing__campaign, marketing__campaign_performance, marketing__platform_campaign_conversion, google_ads.ads_CampaignBasicStats_5447029893, google_ads.ads_CampaignCrossDeviceStats_5447029893, reference__calendar_4_4_5_week.

WITH r AS (
  SELECT week_start_date AS ws, week_end_date AS we
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
cmx AS (
  SELECT campaign_unique_id AS cu, ANY_VALUE(campaign_id) AS cid, ANY_VALUE(ad_platform) AS plat,
    ANY_VALUE(campaign_type) AS ctype, ANY_VALUE(campaign_category) AS cat,
    LOGICAL_OR(ad_platform = 'Google Ads' AND (LOWER(campaign_name) LIKE '%youtube%' OR LOWER(campaign_name) LIKE '%demand gen%')) AS is_excl
  FROM `petcircle-warehouse-cloud.business_layer.marketing__campaign`
  WHERE ad_platform IN ('Google Ads', 'Bing Ads')
  GROUP BY 1
),
pf AS (
  SELECT f.campaign_unique_id AS cu, f.campaign_date AS dt, DIV(DATE_DIFF(r.we, f.campaign_date, DAY), 7) AS k,
    SUM(f.campaign_spend_amount) AS sp, SUM(f.impression_count) AS im, SUM(f.click_count) AS ck
  FROM `petcircle-warehouse-cloud.business_layer.marketing__campaign_performance` f CROSS JOIN r
  WHERE f.campaign_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.we
  GROUP BY 1, 2, 3
),
cv AS (
  SELECT c.campaign_unique_id AS cu, c.campaign_date AS dt, DIV(DATE_DIFF(r.we, c.campaign_date, DAY), 7) AS k,
    SUM(c.platform_order_count) AS o, SUM(c.platform_revenue_amount) AS rev, SUM(c.platform_new_customer_count) AS nc
  FROM `petcircle-warehouse-cloud.business_layer.marketing__platform_campaign_conversion` c CROSS JOIN r
  WHERE c.campaign_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.we
  GROUP BY 1, 2, 3
),
bs AS (
  SELECT CAST(b.campaign_id AS STRING) AS cid, b.segments_date AS dt, SUM(b.metrics_impressions) AS simp
  FROM `petcircle-datalake-cloud.google_ads.ads_CampaignBasicStats_5447029893` b CROSS JOIN r
  WHERE b.segments_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.we AND b.segments_ad_network_type = 'SEARCH'
  GROUP BY 1, 2
),
isd AS (
  SELECT CAST(x.campaign_id AS STRING) AS cid, x.segments_date AS dt, bs.simp,
    SAFE_DIVIDE(bs.simp, x.metrics_search_impression_share) AS elig,
    x.metrics_search_budget_lost_impression_share AS bl, x.metrics_search_rank_lost_impression_share AS rl
  FROM `petcircle-datalake-cloud.google_ads.ads_CampaignCrossDeviceStats_5447029893` x CROSS JOIN r
  JOIN bs ON bs.cid = CAST(x.campaign_id AS STRING) AND bs.dt = x.segments_date
  WHERE x.segments_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.we AND x.segments_ad_network_type = 'SEARCH'
    AND x.metrics_search_impression_share > 0
),
d AS (
  SELECT COALESCE(pf.cu, cv.cu) AS cu, COALESCE(pf.dt, cv.dt) AS dt, COALESCE(pf.k, cv.k) AS k,
    pf.sp, pf.im, pf.ck, cv.o, cv.rev, cv.nc
  FROM pf FULL OUTER JOIN cv ON pf.cu = cv.cu AND pf.dt = cv.dt
),
e AS (
  SELECT d.k, c.cat, c.ctype, c.is_excl, d.sp, d.im, d.ck, d.o, d.rev, d.nc,
    IF(d.nc IS NOT NULL, d.sp, NULL) AS sp_nc,
    IF(c.plat = 'Google Ads', d.sp, NULL) AS sp_g,
    IF(i.elig > 0, d.sp, NULL) AS sp_is,
    i.simp, i.elig, i.bl * i.elig AS bl_w, i.rl * i.elig AS rl_w
  FROM d JOIN cmx c ON c.cu = d.cu
  LEFT JOIN isd i ON c.plat = 'Google Ads' AND i.cid = c.cid AND i.dt = d.dt
),
nb AS (SELECT COUNT(DISTINCT k) AS n FROM e WHERE k BETWEEN 1 AND 12),
g0 AS (
  SELECT cat, GROUPING(cat) AS is_tot, k,
    SUM(sp) AS sp, SUM(IF(ctype = 'Shopping', sp, 0)) AS sp_shop, SUM(im) AS im, SUM(ck) AS ck,
    SUM(o) AS o, SUM(rev) AS rev, SUM(nc) AS nc, SUM(sp_nc) AS sp_nc, SUM(sp_g) AS sp_g, SUM(sp_is) AS sp_is,
    SUM(simp) AS simp, SUM(elig) AS elig, SUM(bl_w) AS bl_w, SUM(rl_w) AS rl_w
  FROM e WHERE NOT is_excl
  GROUP BY GROUPING SETS ((cat, k), (k))
),
g AS (
  SELECT IF(is_tot = 1, 'Total', IFNULL(cat, 'Unmapped')) AS cat, * EXCEPT (cat, is_tot) FROM g0
),
p AS (
  SELECT cat,
    SUM(IF(k = 0, sp, 0)) AS sp0, SUM(IF(k BETWEEN 1 AND 12, sp, 0)) AS sp12,
    SUM(IF(k = 0, sp_shop, 0)) AS shop0, SUM(IF(k = 0, im, 0)) AS im0, SUM(IF(k = 0, ck, 0)) AS ck0,
    SUM(IF(k = 0, o, NULL)) AS o0, SUM(IF(k = 0, rev, NULL)) AS rev0, SUM(IF(k BETWEEN 1 AND 12, rev, NULL)) AS rev12,
    SUM(IF(k = 0, nc, NULL)) AS nc0, SUM(IF(k = 0, sp_nc, NULL)) AS spnc0,
    SUM(IF(k = 0, sp_g, NULL)) AS spg0, SUM(IF(k = 0, sp_is, NULL)) AS spis0,
    SUM(IF(k = 0, simp, NULL)) AS simp0, SUM(IF(k = 0, elig, NULL)) AS el0,
    SUM(IF(k = 0, bl_w, NULL)) AS bl0, SUM(IF(k = 0, rl_w, NULL)) AS rl0,
    SUM(IF(k BETWEEN 1 AND 12, simp, NULL)) AS simp12, SUM(IF(k BETWEEN 1 AND 12, elig, NULL)) AS el12
  FROM g GROUP BY 1
),
ex AS (
  SELECT SUM(IF(k = 0, sp, 0)) AS xs0, SUM(IF(k BETWEEN 1 AND 12, sp, 0)) / (SELECT n FROM nb) AS xs12,
    SUM(IF(k = 0, im, 0)) AS xi0, COUNT(DISTINCT IF(k = 0 AND sp > 0, cat, NULL)) AS xc
  FROM e WHERE is_excl
)
SELECT FORMAT_DATE('%F', (SELECT we FROM r)) AS week_end,
  p.cat AS campaign_category,
  ROUND(sp0, 2) AS spend, ROUND(sp12 / (SELECT n FROM nb), 2) AS spend_l12w,
  ROUND(SAFE_DIVIDE(sp0, sp12 / (SELECT n FROM nb)) - 1, 4) AS spend_vs_l12w_pct,
  ROUND(100 * SAFE_DIVIDE(shop0, sp0), 1) AS shopping_spend_share,
  im0 AS impressions, ck0 AS clicks,
  ROUND(100 * SAFE_DIVIDE(ck0, im0), 2) AS ctr, ROUND(SAFE_DIVIDE(sp0, ck0), 2) AS cpc,
  o0 AS platform_orders, ROUND(rev0, 2) AS platform_revenue,
  ROUND(SAFE_DIVIDE(rev0, sp0), 4) AS platform_roas,
  ROUND(SAFE_DIVIDE(rev12, sp12), 4) AS platform_roas_l12w,
  nc0 AS platform_new_customers, ROUND(SAFE_DIVIDE(spnc0, nc0), 2) AS cost_per_new_customer,
  ROUND(100 * SAFE_DIVIDE(simp0, el0), 1) AS search_is,
  ROUND(100 * SAFE_DIVIDE(simp12, el12), 1) AS search_is_l12w,
  ROUND(100 * (SAFE_DIVIDE(simp0, el0) - SAFE_DIVIDE(simp12, el12)), 1) AS search_is_vs_l12w_pp,
  ROUND(100 * SAFE_DIVIDE(bl0, el0), 1) AS budget_lost_is,
  ROUND(100 * SAFE_DIVIDE(rl0, el0), 1) AS rank_lost_is,
  ROUND(100 * SAFE_DIVIDE(spis0, spg0), 1) AS is_campaign_coverage,
  ROUND(spg0, 2) AS google_spend,
  ROUND(IF(p.cat = 'Total', (SELECT xs0 FROM ex), NULL), 2) AS excluded_spend,
  ROUND(IF(p.cat = 'Total', (SELECT xs12 FROM ex), NULL), 2) AS excluded_spend_l12w,
  IF(p.cat = 'Total', (SELECT xi0 FROM ex), NULL) AS excluded_impressions,
  (SELECT n FROM nb) AS l12w_weeks,
  ROW_NUMBER() OVER (ORDER BY IF(p.cat = 'Total', 2, IF(p.cat = 'Brand', 0, 1)), sp0 DESC) AS sort
FROM p
ORDER BY sort
