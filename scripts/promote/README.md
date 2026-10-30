# promote

Promote a dashboard's reviewed code from the repo to the live dashboard. This is step 6 of the development cycle in the Confluence page "Developing Claude Dashboards: The Development LifeCycle".

| File | What it is |
| --- | --- |
| `SKILL.md` | The procedure Claude follows. Ask Claude to "promote `weekly-trading/<tag>` to the live Weekly Trading Dashboard" and it follows this |
| `promote.py` | Decides what may be written and refuses anything unsafe. Python standard library only, no network access |
| `test_promote.py` | Tests for `promote.py` |

## What it does

The live dashboard stores each dataset's SQL and the page code inside itself, and the scheduled refresh runs the stored SQL. Promotion makes those stored copies match a tagged release in this repo.

1. **plan** compares the repo at the release with an export of the live dashboard and lists exactly what would change, with query diffs.
2. **build** turns the plan into version-pinned write batches.
3. **verify** exports the live dashboard again and confirms it now matches the repo.

## Safety built in

- **Code only, never data.** Patches may contain only a dataset's title, description and stored query, a page file's text, and (opt-in) refresh helper code. A dataset's data file pointer, update time, last-attempt record and refresh schedule are never written. This is checked in code and tested.
- **Drift check.** Given the previous release as a baseline, a live value that differs from it is reported as DRIFT and blocks the promotion, so a fix made directly on the live dashboard is not silently overwritten.
- **No creating datasets.** A dataset that is in the repo but not live blocks the plan. It needs setting up and its first data file created first.
- **Refresh windows.** `build` refuses to run in the Monday refresh window (07:30 to 10:45 Sydney) or the Tuesday Operations top-up window (09:00 to 10:45).
- **Unattended code needs acknowledgement.** Refresh helper code is excluded by default. Including it needs `--include-refresh-code` and, at build time, `--ack-unattended`.
- **Version pinning.** Every write carries the version it was planned against. If anyone changed a document in between, the batch writes nothing.
- **Order.** Dataset definitions are written first and the page last.
- **Release record.** A small `ops/release` document on the live dashboard records the tag, commit and time of the last promotion, which also becomes the baseline for the next one.

## Known limits

- A changed query keeps producing data in its old shape until the next refresh. If the page now expects new columns it can show gaps until a refresh runs. The plan flags this.
- It does not create or delete datasets, and does not change a dataset's connector.
- It is run by a person or by Claude on request. It is not automatic. Automating it needs scheduled tasks to be able to read this repo.
- The comparison treats trailing whitespace in queries as insignificant.

## Running the tests

```
cd scripts/promote
python3 -m unittest test_promote -v
```

## Status

18 tests pass, and a plan run against the real Weekly Trading Dashboard (77 queries, 3 page files) found no differences from the repo, as expected straight after a sync. The write steps (batch writes with the ArtifactData tool) follow its documented behaviour but had not been run against the live dashboard when this was written. The first real promotion should be done with the dashboard owner watching.
