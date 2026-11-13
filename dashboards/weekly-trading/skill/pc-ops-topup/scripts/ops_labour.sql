-- Dataset: ops_labour
-- Title: Labour cost and cost per order by fulfilment centre
-- Tab: Operations
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: {"usage": "ad-hoc", "dashboard": "weekly-trading", "tile": "ops-labour"}
-- Description: Ad-Hoc query (reads petcircle-data-spoke-finance.deputy, outside business_layer). Labour cost, hours, orders closed and cost per order by fulfilment centre (Eastern Creek, Crestmead, Tarneit, Bibra Lake) and National, for the reporting week and the five weeks before it, calculated here instead of copied from the ops team's dashboard. Cost is built from Deputy timesheets: own staff on-costed by site, labour hire at invoiced cost (never on-costed; identified by Deputy pay rules 456, 510 and 511), paid leave attributed to the employee's main site, Fleet excluded, plus the Tarneit standing adjustment (+38 hours, +$1,919.38 a week, added after on-cost). Orders closed are fulfilment orders closed by the warehouse (all stores) from logistics__customer_order_delivery. Budgets come from inventory__targets_warehouse_by_day. Reads petcircle-data-spoke-finance.deputy.resource_timesheet, operational_unit, company and employee (employee id and base pay rule only), logistics__customer_order_delivery, inventory__targets_warehouse_by_day, reference__calendar_4_4_5_week. Same columns as the ops_labour rows the ops team's dashboard used to supply, plus hrs, own_hrs and con_hrs.

-- dashboard: weekly-trading | tile: ops-labour
WITH wk AS (
  SELECT week_start_date AS ws, week_end_date AS we
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
-- One row per fulfilment centre. On-cost factors and the Tarneit standing adjustment are the ops team's
-- settled values (ops WBR, Labour & cost appendix). They are business rules, not data: change them here only
-- with the dashboard owner's sign-off, and say so in the pull request.
siteref AS (
  SELECT * FROM UNNEST([
    STRUCT('EC' AS fc, 'Eastern Creek' AS fc_name, 'EC - ' AS pfx, 'NSW-WH Eastern Creek' AS wh, 1.1810 AS oncost, 0.0 AS adj_hrs, 0.0 AS adj_cost),
    STRUCT('BNE', 'Crestmead', 'QLD - ', 'QLD-WH Crestmead', 1.1754, 0.0, 0.0),
    STRUCT('MEL', 'Tarneit', 'VIC - ', 'VIC-WH Tarneit', 1.1743, 38.0, 1919.38),
    STRUCT('PER', 'Bibra Lake', 'WA - ', 'WA-WH Bibra Lake', 1.1816, 0.0, 0.0)
  ])
),
-- Deputy timesheets for the reporting week and the five before it (Sydney-local dates).
-- Labour hire is the three Deputy pay rules 456 / 510 / 511 (Hoban / LSG / Essential). Discarded timesheets are no-shows.
ts AS (
  SELECT
    t.employee_id,
    DATE_TRUNC(DATE(LEFT(t.date, 10)), WEEK(MONDAY)) AS week_start,
    c.company_name,
    COALESCE(t.is_leave, FALSE) AS is_leave,
    COALESCE(e.contract_base_pay_rule IN (456, 510, 511), FALSE) AS is_con,
    t.total_time AS hrs,
    t.cost AS cost
  FROM `petcircle-data-spoke-finance.deputy.resource_timesheet` t
  CROSS JOIN wk
  LEFT JOIN `petcircle-data-spoke-finance.deputy.operational_unit` ou ON ou.id = t.operational_unit
  LEFT JOIN `petcircle-data-spoke-finance.deputy.company` c ON c.id = ou.company_id
  LEFT JOIN (SELECT id, contract_base_pay_rule FROM `petcircle-data-spoke-finance.deputy.employee`) e ON e.id = t.employee_id
  WHERE NOT COALESCE(t._fivetran_deleted, FALSE)
    AND NOT COALESCE(t.discarded, FALSE)
    AND DATE(LEFT(t.date, 10)) BETWEEN DATE_SUB(wk.ws, INTERVAL 35 DAY) AND wk.we
),
-- Worked (non-leave) time at the four sites. Fleet is excluded. Function follows the Deputy company; anything that is
-- not Inbound, Outbound / AMR, Dock or Weekend is Support (Inventory and Planning).
worked AS (
  SELECT
    ts.employee_id, ts.week_start, ts.company_name, ts.is_con, ts.hrs, ts.cost, s.fc,
    CASE
      WHEN REGEXP_CONTAINS(ts.company_name, r'Inbound') THEN 'in'
      WHEN REGEXP_CONTAINS(ts.company_name, r'Outbound|AMR') THEN 'out'
      WHEN REGEXP_CONTAINS(ts.company_name, r'Dock') THEN 'dock'
      WHEN REGEXP_CONTAINS(ts.company_name, r'Weekend') THEN 'wknd'
      ELSE 'supp'
    END AS fn
  FROM ts
  JOIN siteref s ON STARTS_WITH(ts.company_name, s.pfx)
  WHERE NOT ts.is_leave AND ts.company_name NOT LIKE '% - Fleet'
),
-- Leave timesheets carry no company, so paid leave goes to the company where that employee worked the most hours that week.
emp_co AS (
  SELECT employee_id, week_start, company_name, ANY_VALUE(fc) AS fc, ANY_VALUE(fn) AS fn, SUM(hrs) AS h
  FROM worked
  WHERE NOT is_con
  GROUP BY 1, 2, 3
),
prim AS (
  SELECT * EXCEPT (rn) FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY employee_id, week_start ORDER BY h DESC, company_name) AS rn FROM emp_co
  ) WHERE rn = 1
),
-- Fallback for staff who worked no hours at the sites that week (for example a full week of leave): their usual company
-- across the six weeks.
prim_any AS (
  SELECT employee_id, fc, fn FROM (
    SELECT employee_id, company_name, ANY_VALUE(fc) AS fc, ANY_VALUE(fn) AS fn,
      ROW_NUMBER() OVER (PARTITION BY employee_id ORDER BY SUM(h) DESC, company_name) AS rn
    FROM emp_co
    GROUP BY employee_id, company_name
  ) WHERE rn = 1
),
leave AS (
  SELECT COALESCE(p.fc, a.fc) AS fc, COALESCE(p.fn, a.fn) AS fn, ts.week_start, FALSE AS is_con,
    SUM(ts.hrs) AS hrs, SUM(ts.cost) AS cost
  FROM ts
  LEFT JOIN prim p ON p.employee_id = ts.employee_id AND p.week_start = ts.week_start
  LEFT JOIN prim_any a ON a.employee_id = ts.employee_id
  WHERE ts.is_leave AND NOT ts.is_con AND ts.cost > 0 AND COALESCE(p.fc, a.fc) IS NOT NULL
  GROUP BY 1, 2, 3
),
lines AS (
  SELECT fc, fn, week_start, is_con, SUM(hrs) AS hrs, SUM(cost) AS base_cost FROM worked GROUP BY 1, 2, 3, 4
  UNION ALL
  SELECT fc, fn, week_start, is_con, hrs, cost FROM leave
),
-- Own-staff cost is on-costed; contractor cost is the invoiced rate and is never on-costed.
costed AS (
  SELECT l.fc, l.fn, l.week_start, l.is_con, l.hrs,
    IF(l.is_con, l.base_cost, l.base_cost * s.oncost) AS cost
  FROM lines l JOIN siteref s ON s.fc = l.fc
),
labour AS (
  SELECT
    c.fc, c.week_start,
    SUM(IF(c.is_con, 0, c.cost)) AS own_cost_ex_adj,
    SUM(IF(c.is_con, c.cost, 0)) AS con_cost,
    SUM(IF(c.is_con, 0, c.hrs)) AS own_hrs_ex_adj,
    SUM(IF(c.is_con, c.hrs, 0)) AS con_hrs,
    SUM(IF(c.fn = 'in', c.cost, 0)) AS in_cost,
    SUM(IF(c.fn = 'out', c.cost, 0)) AS out_cost,
    SUM(IF(c.fn = 'dock', c.cost, 0)) AS dock_cost,
    SUM(IF(c.fn = 'wknd', c.cost, 0)) AS wknd_cost,
    SUM(IF(c.fn = 'supp', c.cost, 0)) AS supp_cost
  FROM costed c
  GROUP BY 1, 2
),
-- Orders closed by the fulfilment warehouse in the week (fulfilment orders with status Closed, all stores handled at the site,
-- matching the scope of the labour cost).
ord AS (
  SELECT sr.fc, DATE_TRUNC(f.closed_date, WEEK(MONDAY)) AS week_start, SUM(f.count_fulfilment_order_closed) AS orders
  FROM `petcircle-warehouse-cloud.business_layer.logistics__customer_order_delivery` d
  CROSS JOIN wk
  CROSS JOIN UNNEST(d.fulfilment_order) f
  JOIN siteref sr ON sr.wh = f.fulfilment_warehouse
  WHERE d.order_created_date >= DATE_SUB(wk.ws, INTERVAL 160 DAY)
    AND f.closed_date BETWEEN DATE_SUB(wk.ws, INTERVAL 35 DAY) AND wk.we
  GROUP BY 1, 2
),
-- Budgets: weekly labour cost and order budgets are spread evenly over the 7 days, so they sum back to the week.
-- The cost-per-order budget is held flat across the week.
tgt AS (
  SELECT sr.fc, DATE_TRUNC(t.calendar_date, WEEK(MONDAY)) AS week_start,
    SUM(t.daily_target_warehouse_labour_cost) AS cost_tgt,
    SUM(t.daily_target_order_count) AS orders_tgt,
    AVG(t.daily_target_warehouse_cost_per_order) AS cpo_tgt
  FROM `petcircle-warehouse-cloud.business_layer.inventory__targets_warehouse_by_day` t
  CROSS JOIN wk
  JOIN siteref sr ON sr.wh = t.warehouse_name
  WHERE t.calendar_date BETWEEN DATE_SUB(wk.ws, INTERVAL 35 DAY) AND wk.we
  GROUP BY 1, 2
),
site_week AS (
  SELECT
    s.fc, s.fc_name, l.week_start,
    o.orders,
    l.own_cost_ex_adj + s.adj_cost AS own_cost,
    l.con_cost,
    l.own_hrs_ex_adj + s.adj_hrs AS own_hrs,
    l.con_hrs,
    l.in_cost, l.out_cost, l.dock_cost, l.wknd_cost, l.supp_cost,
    g.cost_tgt, g.orders_tgt, g.cpo_tgt
  FROM labour l
  JOIN siteref s ON s.fc = l.fc
  LEFT JOIN ord o ON o.fc = l.fc AND o.week_start = l.week_start
  LEFT JOIN tgt g ON g.fc = l.fc AND g.week_start = l.week_start
),
pooled AS (
  SELECT * FROM site_week
  UNION ALL
  SELECT 'ALL', 'National', week_start,
    SUM(orders), SUM(own_cost), SUM(con_cost), SUM(own_hrs), SUM(con_hrs),
    SUM(in_cost), SUM(out_cost), SUM(dock_cost), SUM(wknd_cost), SUM(supp_cost),
    SUM(cost_tgt), SUM(orders_tgt),
    ROUND(SAFE_DIVIDE(SUM(cpo_tgt * orders_tgt), SUM(orders_tgt)), 2)
  FROM site_week
  GROUP BY week_start
),
fin AS (
  SELECT
    p.fc, p.fc_name,
    FORMAT_DATE('%Y-%m-%d', p.week_start) AS week_start,
    p.week_start = wk.ws AS is_latest,
    ROUND(p.orders, 0) AS orders,
    ROUND(p.own_cost + p.con_cost, 2) AS cost,
    ROUND(p.own_cost, 2) AS own_cost,
    ROUND(p.con_cost, 2) AS con_cost,
    ROUND(p.own_hrs + p.con_hrs, 1) AS hrs,
    ROUND(p.own_hrs, 1) AS own_hrs,
    ROUND(p.con_hrs, 1) AS con_hrs,
    ROUND(SAFE_DIVIDE(p.own_cost + p.con_cost, p.orders), 4) AS cpo,
    ROUND(SAFE_DIVIDE(p.own_cost + p.con_cost, p.own_hrs + p.con_hrs), 4) AS cph,
    ROUND(100 * SAFE_DIVIDE(p.con_hrs, p.own_hrs + p.con_hrs), 4) AS contractor_mix,
    ROUND(p.cpo_tgt, 4) AS cpo_tgt,
    ROUND(p.cost_tgt, 2) AS cost_tgt,
    ROUND(p.orders_tgt, 0) AS orders_tgt,
    ROUND(p.out_cost, 2) AS out_cost,
    ROUND(p.in_cost, 2) AS in_cost,
    ROUND(p.dock_cost, 2) AS dock_cost,
    ROUND(p.wknd_cost, 2) AS wknd_cost,
    ROUND(p.supp_cost, 2) AS supp_cost,
    FORMAT_DATE('%Y-%m-%d', wk.we) AS week_end
  FROM pooled p
  CROSS JOIN wk
)
SELECT
  fin.*,
  ROUND(cpo - LAG(cpo) OVER w, 4) AS cpo_vs_pw,
  ROUND(cost - LAG(cost) OVER w, 2) AS cost_vs_pw,
  ROUND(orders - LAG(orders) OVER w, 0) AS orders_vs_pw,
  ROUND(cph - LAG(cph) OVER w, 4) AS cph_vs_pw,
  ROUND(contractor_mix - LAG(contractor_mix) OVER w, 4) AS contractor_mix_vs_pw,
  ROUND(out_cost - LAG(out_cost) OVER w, 2) AS out_cost_vs_pw,
  ROUND(in_cost - LAG(in_cost) OVER w, 2) AS in_cost_vs_pw,
  ROUND(dock_cost - LAG(dock_cost) OVER w, 2) AS dock_cost_vs_pw,
  ROUND(wknd_cost - LAG(wknd_cost) OVER w, 2) AS wknd_cost_vs_pw,
  ROUND(supp_cost - LAG(supp_cost) OVER w, 2) AS supp_cost_vs_pw,
  ROUND(cpo - cpo_tgt, 4) AS cpo_vs_tgt,
  ROUND(cost - cost_tgt, 2) AS cost_vs_tgt,
  ROUND(SAFE_DIVIDE(cpo, FIRST_VALUE(cpo) OVER w) - 1, 4) AS cpo_vs_first
FROM fin
WINDOW w AS (PARTITION BY fc ORDER BY week_start)
ORDER BY week_start, fc
