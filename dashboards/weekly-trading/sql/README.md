# SQL

One file per dataset, taken from the query each dataset runs against BigQuery. Each file starts with a comment header giving the dataset id, title, tab, connector and tool, project, job labels and description. The query itself is unchanged from what the dashboard stores.

**Source of truth.** The live refresh still reads each query from the dashboard's own dataset documents, not from this repo. These files are a versioned copy, so any change to a query must be made in both places until the refresh is pointed at the repo.

Run queries as stored. They anchor themselves to the latest complete 445 week, so no parameters are needed. `_voc_text.sql.txt` is the query that reads survey comment text for the CX coding step; its output is customer personal data and must never be stored or shared (see `docs/runbook.md`).

The ten datasets below have no SQL here. The four CX comment datasets are rebuilt from coded survey comments (`src/voc.py`, `config/voc_rubric.md`), and the six Operations datasets are read from the operations team's own dashboard by `skill/pc-ops-topup/`.

## Highlights

| Dataset | Title |
| --- | --- |
| [`cal`](cal.sql) | Reporting week calendar |
| [`fy_periods`](fy_periods.sql) | FY months and YTD |
| [`fy_weeks`](fy_weeks.sql) | FY weeks vs budget |
| [`levers`](levers.sql) | Strategic levers |
| [`scorecard`](scorecard.sql) | Commercial scorecard |
| [`scorecard_weekly`](scorecard_weekly.sql) | Scorecard 13-week series |
| [`week_ahead`](week_ahead.sql) | Week ahead targets |

## CX

| Dataset | Title |
| --- | --- |
| [`cx_contact_reasons`](cx_contact_reasons.sql) | Contacts by reason |
| [`cx_contacts`](cx_contacts.sql) | Customer contacts |
| [`cx_csat_channel`](cx_csat_channel.sql) | CSAT by channel |
| [`cx_csat_handler`](cx_csat_handler.sql) | CSAT by handler |
| [`cx_csat_weekly`](cx_csat_weekly.sql) | Weekly CSAT trend |
| [`cx_nps`](cx_nps.sql) | NPS 13-week window |
| [`cx_nps_weekly`](cx_nps_weekly.sql) | Weekly NPS |
| [`cx_responses`](cx_responses.sql) | NPS responses (no text) |
| [`cx_segments`](cx_segments.sql) | NPS by order type |

## Commercial

| Dataset | Title |
| --- | --- |
| [`app_vs_web`](app_vs_web.sql) | App vs website orders |
| [`channel_trend`](channel_trend.sql) | Channel share trend |
| [`commercial_explorer`](commercial_explorer.sql) | Commercial explorer cube |
| [`food_crosssell`](food_crosssell.sql) | Food basket cross-sell |
| [`food_vs_nonfood`](food_vs_nonfood.sql) | Food vs non-food orders |
| [`orders_mix`](orders_mix.sql) | Orders and AOV mix |

## Media & Funnel

| Dataset | Title |
| --- | --- |
| [`mf_acq_channels`](mf_acq_channels.sql) | Acquisition channel scorecard |
| [`mf_acq_weekly`](mf_acq_weekly.sql) | Weekly sessions, orders, spend |
| [`mf_channel`](mf_channel.sql) | Orders bridge by channel |
| [`mf_coupons`](mf_coupons.sql) | Coupon orders and cost |
| [`mf_device`](mf_device.sql) | Sessions by device |
| [`mf_funnel`](mf_funnel.sql) | Funnel metric matrix |
| [`mf_headline`](mf_headline.sql) | Sessions, CVR and orders |
| [`mf_landing`](mf_landing.sql) | Landing surface deep dive |
| [`mf_region`](mf_region.sql) | Sessions by region |
| [`mf_sem_category`](mf_sem_category.sql) | SEM by category |
| [`mf_social`](mf_social.sql) | Paid Social (Facebook) detail |
| [`mf_weekly`](mf_weekly.sql) | Sessions 13-week trend |

## Customer

| Dataset | Title |
| --- | --- |
| [`a92_flow`](a92_flow.sql) | A92 base flow, 13 weeks |
| [`cohort_channel`](cohort_channel.sql) | Cohort by channel AOV |
| [`cust_overview`](cust_overview.sql) | Customer overview |
| [`cust_wbr`](cust_wbr.sql) | Customer WBR tables |
| [`new_by_category`](new_by_category.sql) | New customers by category |
| [`new_by_channel`](new_by_channel.sql) | New customers by acquisition channel |
| [`rfm_segments`](rfm_segments.sql) | RFM buckets and segments |
| [`super_users`](super_users.sql) | Super users |
| [`tenure`](tenure.sql) | A92 base by tenure |
| [`value_drivers`](value_drivers.sql) | Customer value drivers |

## Auto Delivery

| Dataset | Title |
| --- | --- |
| [`ad_brands`](ad_brands.sql) | Top AD brands |
| [`ad_cancel`](ad_cancel.sql) | AD cancellation flow |
| [`ad_cohort`](ad_cohort.sql) | AD1 cohort progression |
| [`ad_funnel`](ad_funnel.sql) | AD order funnel |
| [`ad_groups`](ad_groups.sql) | AD group net movement |
| [`ad_lenses`](ad_lenses.sql) | AD share on four lenses |
| [`ad_move`](ad_move.sql) | AD live base movement |
| [`ad_order_type`](ad_order_type.sql) | AD order type mix |
| [`ad_penetration`](ad_penetration.sql) | AD penetration |
| [`ad_vs_nonad`](ad_vs_nonad.sql) | AD vs non-AD orders |

## Category

| Dataset | Title |
| --- | --- |
| [`cat_books`](cat_books.sql) | Category performance by book |
| [`cat_brands`](cat_brands.sql) | Brand movers by book |
| [`cat_promos`](cat_promos.sql) | Promotional performance |
| [`cat_subcats`](cat_subcats.sql) | Trading by sub-category |

## Price

| Dataset | Title |
| --- | --- |
| [`pr_discounts`](pr_discounts.sql) | Discount and funding waterfall |
| [`pr_index`](pr_index.sql) | Price index by pricing group |
| [`pr_index_comp`](pr_index_comp.sql) | Price index by competitor |
| [`pr_index_trend`](pr_index_trend.sql) | Price index 13-week trend |
| [`pr_irritants`](pr_irritants.sql) | KVI lines above market |
| [`pr_price_match`](pr_price_match.sql) | Price-match summary |
| [`pr_subcats`](pr_subcats.sql) | Price position by category |

## Inventory

| Dataset | Title |
| --- | --- |
| [`inv_books`](inv_books.sql) | Stock, SLOB and OOS by book |
| [`inv_concentration`](inv_concentration.sql) | Revenue concentration, 30 days |
| [`inv_cover`](inv_cover.sql) | Stock by days of cover |
| [`inv_cover_trend`](inv_cover_trend.sql) | Days-cover mix, 6 weeks |
| [`inv_health`](inv_health.sql) | Inventory health headline |
| [`inv_oos_matrix`](inv_oos_matrix.sql) | OOS % by book x warehouse |
| [`inv_oos_wh`](inv_oos_wh.sql) | SKU availability by warehouse |
| [`inv_range`](inv_range.sql) | SKU / variant productivity |
| [`inv_slob_lifecycle`](inv_slob_lifecycle.sql) | SLOB by lifecycle stage |

## Operations

| Dataset | Title |
| --- | --- |
| [`ops_delivery`](ops_delivery.sql) | Delivery promise by warehouse |
