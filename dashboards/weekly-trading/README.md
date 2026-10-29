# Weekly Trading Dashboard

The Pet Circle Weekly Trading Dashboard is the company's weekly trading pack. It gives the business one place to see how Pet Circle traded in the latest reporting week, with each result set against last week, the same 445 week last year, the prior 12-week average and budget where those apply.

It is a Claude artifact built from tables in BigQuery, and is refreshed automatically each week.

**Live dashboard:** https://claude.ai/artifact/37trWrETCbW7eD385HZcWV

## Audience and use

The pack is read at the start of each trading week by commercial, marketing, customer, category, pricing, inventory and operations stakeholders. It is designed to answer "how did we trade last week, and why" without anyone needing to run their own queries.

## What it covers

The dashboard has ten tabs:

| Tab | What it shows |
| --- | --- |
| Highlights | Headline scorecard for the reporting week, trend lines, week-ahead targets, FY weeks and months against budget, and the strategic levers (Auto Delivery, Food and App penetration) |
| CX | NPS against target, CSAT by channel and handler, contacts by reason, and coded survey comments grouped into themes and clusters |
| Commercial | Orders, revenue, AOV and mix by channel, customer status and delivery state, with an explorer for slicing product revenue and margin |
| Media & Funnel | Sessions, conversion and orders by acquisition channel, device, region and landing surface, plus paid search, paid social and coupon performance |
| Customer | The 92-day active base and its flow, tenure, RFM segments, new customers by channel and category, super users, and customer value drivers |
| Auto Delivery | AD penetration across four lenses, live base movement, order funnel by AD order number, cancellations, cohort progression, top brands, and AD against non-AD baskets |
| Category | Trading by book and sub-category against plan, brand movers, and promotional campaign performance |
| Price | Auto Delivery price index against competitors for KVI, Core and Tail lines, KVI lines above market, price-match and the discount and funding waterfall |
| Inventory | Stock, SLOB and out-of-stock by book and warehouse, days of cover, range productivity and revenue concentration |
| Operations | Cost per order, labour, productivity, DIFOT, service levels, AMR uptime and delivery promise by fulfilment centre |

## Data

The dashboard is built from 87 datasets, one or more per tab. Most are produced by SQL against the `business_layer` datasets in BigQuery and saved into the dashboard as files. The exceptions are:

- **Operations** (`ops_labour`, `ops_prod`, `ops_service`, `ops_amr`, `ops_difot`, `ops_meta`): read from the operations team's own weekly dashboard rather than queried from BigQuery. A banner shows when that dashboard is behind this one.
- **CX comment themes** (`cx_themes`, `cx_clusters`, `cx_driver`, `cx_voc_codes`): new survey comments are coded against a fixed rubric each week and the rows recomputed from the coded-comment store. Comment text is not stored in the dashboard; responses carry a hashed id only.

All weeks are 445 reporting weeks. The reporting week, its month and quarter, the last-year comparison week and the plan label are resolved once from the calendar dataset (`cal`) and used throughout.

## Refresh

| When | What |
| --- | --- |
| Monday, 8am Sydney time | A scheduled task re-runs the queries and saves the results into the dashboard |
| Tuesday morning | Operations top-up: re-reads the operations team's dashboard and republishes the six Operations datasets only, using the `pc-ops-topup` skill |

Each dataset records when it was last updated, and the page shows a stale banner if a refresh has not landed.

## Contents of this folder

| Path | What it holds |
| --- | --- |
| `sql/` | The query behind each of the 77 BigQuery-backed datasets, with an index by tab. See `sql/README.md` |
| `src/` | `refresh_lib.py` (query wrapping, checksums and the publish gate) and `voc.py` (CX comment theme rebuild) |
| `config/` | `voc_rubric.md`, the fixed rubric used to code survey comments |
| `templates/` | The dashboard page: `index.html`, `app.js` and `explorer.js` |
| `skill/pc-ops-topup/` | The Tuesday Operations top-up skill and its `scripts/ops.py` |
| `docs/` | `runbook.md` (the Monday refresh procedure) and `scheduled-tasks.md` |

### Source of truth

This folder is currently a versioned copy. The live dashboard still runs its queries and page from its own store, and the scheduled refresh reads the runbook and helper scripts from there too. Until the refresh is pointed at this repo, any change to a query, the page or a script must be made in both places.

The other 10 datasets have no SQL: the four CX comment datasets are rebuilt from coded survey comments, and the six Operations datasets are read from the operations team's own dashboard.

## Ownership

Maintained by the Pet Circle Analytics team. Changes to metric definitions or comparison bases should go through a pull request.
