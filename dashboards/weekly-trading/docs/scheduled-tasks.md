# Scheduled tasks

Three scheduled tasks look after this dashboard. All times are Sydney time. The task prompts live in the scheduled-task settings, not in this repo; this page records what each one does and which files it relies on.

| Task | When | What it does |
| --- | --- | --- |
| Monday refresh | Monday 8:00am | Follows `docs/runbook.md`: runs every query in `sql/` against BigQuery, rebuilds the CX comment themes and the Operations datasets, runs the gate, and only if everything passes uploads the new files and updates every dataset. On any failure nothing is published and Will Kent is alerted by Slack and push notification. |
| Tuesday Operations top-up | Tuesday 9:47am | Runs the `pc-ops-topup` skill (`skill/pc-ops-topup/`) to re-read the operations team's dashboard and republish the five Operations datasets and `ops_labour` only. Labour is calculated from Deputy (the same query as the Monday refresh) and checked against the ops team's page; if they differ, one message is posted to #analytics-dashboard-alerts. |
| Monday freshness check | Monday 10:30am | Read-only check that the dashboard shows the week that just ended and that no dataset recorded a failed refresh. Posts a heartbeat or an alert to the analytics dashboard alerts channel. |

## Files the refresh depends on

- `docs/runbook.md`: the step-by-step procedure the Monday task follows.
- `src/refresh_lib.py`: helpers for converting query results, checksums and the publish gate.
- `src/voc.py`, `config/voc_rubric.md` and `sql/_voc_text.sql.txt`: the CX comment coding step. Comment text is customer personal data. It stays in scratch space during the run and is deleted afterwards.
- `sql/ops_labour.sql`: reads Deputy timesheets from `petcircle-data-spoke-finance.deputy`. The account that runs the Monday refresh needs access to that dataset as well as `petcircle-data-ca`.
- `skill/pc-ops-topup/`: the owner-approved skill and its `scripts/ops.py`. The runbook checks the script's SHA-256 before running it.

## Datasets without SQL

`cx_clusters`, `cx_driver`, `cx_themes`, `cx_voc_codes`, `ops_amr`, `ops_difot`, `ops_meta`, `ops_prod`, `ops_service`.
