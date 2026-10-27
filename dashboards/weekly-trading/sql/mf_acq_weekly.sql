-- Dataset: mf_acq_weekly
-- Title: Weekly sessions, orders, spend
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Thirteen weekly rows per acquisition channel group for the trend chart. Reads online__session, marketing__campaign_performance, marketing__campaign, marketing__ad_platform, reference__calendar_4_4_5_week. Campaigns for other businesses (Bonnodog, Pharmacy) are excluded from spend.

WITH r AS (
  SELECT week_start_date AS ws, week_end_date AS we
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
w AS (
  SELECT DIV(DATE_DIFF(r.we, s.session_start_date, DAY), 7) AS k, s.acquisition_channel_group AS grp,
    SUM(s.session_count) AS s, SUM(s.session_count_has_converted) AS o
  FROM `petcircle-warehouse-cloud.business_layer.online__session` s CROSS JOIN r
  WHERE s.session_start_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.we
    AND s.business_line = 'Pet Circle' AND s.bot_likelihood_category = 'Likely Human'
  GROUP BY 1, 2
),
sp AS (
  SELECT DIV(DATE_DIFF(r.we, f.campaign_date, DAY), 7) AS k,
    CASE WHEN p.ad_media_type = 'Paid Social' THEN 'Social'
      WHEN p.ad_media_type = 'Paid Display' THEN 'Other'
      WHEN p.ad_platform IN ('Google Ads', 'Bing Ads') THEN 'SEM'
      ELSE 'Unplaced' END AS grp,
    SUM(f.campaign_spend_amount) AS spend
  FROM `petcircle-warehouse-cloud.business_layer.marketing__campaign_performance` f CROSS JOIN r
  JOIN `petcircle-warehouse-cloud.business_layer.marketing__campaign` cm ON cm.campaign_unique_id = f.campaign_unique_id
  LEFT JOIN `petcircle-warehouse-cloud.business_layer.marketing__ad_platform` p ON p.ad_platform = cm.ad_platform
  WHERE f.campaign_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.we
    AND NOT REGEXP_CONTAINS(LOWER(cm.campaign_name), r'bonno|\|\s*pharmacy\s*\|')
  GROUP BY 1, 2
)
SELECT FORMAT_DATE('%F', r.we) AS week_end,
  FORMAT_DATE('%F', DATE_SUB(r.ws, INTERVAL 7 * w.k DAY)) AS week_start,
  w.k AS weeks_ago, w.grp AS channel_group, w.s AS sessions, w.o AS orders,
  ROUND(sp.spend, 2) AS spend
FROM w CROSS JOIN r
LEFT JOIN sp ON sp.k = w.k AND sp.grp = w.grp AND sp.grp != 'Unplaced'
ORDER BY w.k DESC, w.s DESC
