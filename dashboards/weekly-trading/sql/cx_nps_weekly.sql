-- Dataset: cx_nps_weekly
-- Title: Weekly NPS
-- Tab: CX
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Weekly NPS and band mix across the 13-week window, with the target of 80. Reads customer__customer_review, reference__calendar_4_4_5_week.

WITH wk AS (SELECT week_end_date AS we, DATE_SUB(week_end_date, INTERVAL 90 DAY) AS ws FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE), r AS (SELECT DATE_TRUNC(v.review_date, WEEK(MONDAY)) AS week_start, v.review_id, v.net_promoter_count AS np, v.review_count_promoter AS pr, v.review_count_neutral AS pa, v.review_count_detractor AS de, v.review_text, v.customer_review_order_mapping[SAFE_OFFSET(0)].order_id AS oid FROM `petcircle-warehouse-cloud.business_layer.customer__customer_review` v CROSS JOIN wk WHERE v.review_date BETWEEN wk.ws AND wk.we) SELECT CAST(r.week_start AS STRING) AS week_start, COUNT(*) AS n, ROUND(SUM(r.np) / COUNT(*) * 100, 1) AS nps, ROUND(SUM(r.pr) / COUNT(*) * 100, 1) AS promoter_pct, ROUND(SUM(r.pa) / COUNT(*) * 100, 1) AS passive_pct, ROUND(SUM(r.de) / COUNT(*) * 100, 1) AS detractor_pct, 80.0 AS target, CAST(ANY_VALUE(wk.we) AS STRING) AS week_end FROM r CROSS JOIN wk GROUP BY r.week_start ORDER BY r.week_start
