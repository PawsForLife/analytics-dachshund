-- Dataset: mf_social
-- Title: Paid Social (Facebook) detail
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Facebook paid social spend, delivery and click metrics by campaign category against the prior-12-week average, next to site-attributed Paid Social orders. Reads marketing__campaign_performance, marketing__campaign, marketing__ad_platform, marketing__platform_campaign_conversion, online__session, reference__calendar_4_4_5_week. Campaigns for other businesses (Bonnodog, Pharmacy) are excluded.

WITH r AS (
  SELECT week_start_date AS ws, week_end_date AS we
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
pc AS (
  SELECT f.campaign_unique_id, f.campaign_date, SUM(f.campaign_spend_amount) AS spend,
    SUM(f.impression_count) AS imp, SUM(f.click_count) AS clk
  FROM `petcircle-warehouse-cloud.business_layer.marketing__campaign_performance` f CROSS JOIN r
  WHERE f.campaign_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.we
  GROUP BY 1, 2
),
cv AS (
  SELECT x.campaign_unique_id, x.campaign_date, SUM(x.platform_order_count) AS po, SUM(x.platform_revenue_amount) AS prev
  FROM `petcircle-warehouse-cloud.business_layer.marketing__platform_campaign_conversion` x CROSS JOIN r
  WHERE x.campaign_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.we
  GROUP BY 1, 2
),
fb AS (
  SELECT DIV(DATE_DIFF(r.we, pc.campaign_date, DAY), 7) AS k, IFNULL(cm.campaign_category, 'Unknown') AS cat,
    pc.spend, pc.imp, pc.clk, cv.po, cv.prev
  FROM pc CROSS JOIN r
  JOIN `petcircle-warehouse-cloud.business_layer.marketing__campaign` cm ON cm.campaign_unique_id = pc.campaign_unique_id
  JOIN `petcircle-warehouse-cloud.business_layer.marketing__ad_platform` p ON p.ad_platform = cm.ad_platform
  LEFT JOIN cv ON cv.campaign_unique_id = pc.campaign_unique_id AND cv.campaign_date = pc.campaign_date
  WHERE p.ad_media_type = 'Paid Social' AND cm.ad_platform = 'Facebook Ads'
    AND NOT REGEXP_CONTAINS(LOWER(cm.campaign_name), r'bonno|\|\s*pharmacy\s*\|')
),
nb AS (SELECT COUNT(DISTINCT k) AS n FROM fb WHERE k BETWEEN 1 AND 12),
site AS (
  SELECT SUM(s.session_count_has_converted) AS o
  FROM `petcircle-warehouse-cloud.business_layer.online__session` s CROSS JOIN r
  WHERE s.session_start_date BETWEEN r.ws AND r.we
    AND s.business_line = 'Pet Circle' AND s.bot_likelihood_category = 'Likely Human'
    AND s.acquisition_channel = 'Paid Social'
),
g AS (
  SELECT cat,
    SUM(IF(k = 0, spend, 0)) AS sp, SUM(IF(k BETWEEN 1 AND 12, spend, 0)) / (SELECT n FROM nb) AS sp_b,
    SUM(IF(k = 0, imp, 0)) AS imp, SUM(IF(k = 0, clk, 0)) AS clk,
    SUM(IF(k = 0, po, NULL)) AS po, SUM(IF(k = 0, prev, NULL)) AS prev
  FROM fb GROUP BY 1
),
u AS (
  SELECT cat, sp, sp_b, imp, clk, po, prev, 0 AS is_total FROM g
  UNION ALL
  SELECT 'Total', SUM(sp), SUM(sp_b), SUM(imp), SUM(clk), SUM(po), SUM(prev), 1 FROM g
)
SELECT FORMAT_DATE('%F', (SELECT we FROM r)) AS week_end,
  cat AS campaign_category,
  ROUND(sp, 2) AS spend, ROUND(sp_b, 2) AS spend_l12w,
  imp AS impressions, clk AS clicks,
  ROUND(100 * SAFE_DIVIDE(clk, imp), 4) AS ctr,
  ROUND(SAFE_DIVIDE(sp, clk), 4) AS cpc,
  ROUND(1000 * SAFE_DIVIDE(sp, imp), 4) AS cpm,
  IF(is_total = 1, (SELECT o FROM site), NULL) AS site_orders,
  ROUND(po, 2) AS platform_orders, ROUND(prev, 2) AS platform_revenue,
  ROUND(SAFE_DIVIDE(prev, sp), 4) AS platform_roas,
  ROW_NUMBER() OVER (ORDER BY is_total, sp DESC) AS sort
FROM u
ORDER BY sort
