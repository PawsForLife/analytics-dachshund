# dev-copy

Make a private dev copy of a Claude dashboard so a git branch can be developed and tested against production's current data.

| File | What it is |
| --- | --- |
| `SKILL.md` | The procedure Claude follows end to end. Ask Claude to "make a dev copy of the Weekly Trading Dashboard for branch `feature/x`" and it follows this |
| `dev_copy.py` | The deterministic parts: listing the data files to copy, rewriting the dataset documents for the copy, building write batches, and safety checks. Python standard library only, no network access |
| `test_dev_copy.py` | Tests for `dev_copy.py` |

## Why a skill plus a script

Creating a dashboard, copying its data files and writing its documents are done with Claude's Artifact tools, which are not available to a plain command line. So Claude drives those steps. Everything that can be done deterministically lives in `dev_copy.py` so it is reviewed, tested and gives the same answer every time.

## What a dev copy is

- A new, private dashboard titled `DEV: <title> (<branch>)`.
- The same page and dataset definitions as production, so queries and layout match.
- Its own copies of production's current data files, so it never touches production's files.
- No refresh schedule and no stale-after warning. It is a snapshot taken when it was made.
- Not read by any scheduled task, and never shared.

By default the production runbook and helper scripts (`ops/refresh`) are not copied, because refresh code is developed in this repo.

## Safety checks built in

- `finalise` refuses to run if the dev link is the same artifact as production.
- Every generated batch records the dev link, and `verify` checks that each batch targets only the dev copy.
- `verify` checks every dataset points at a copied file, and none at a production file.
- Documents over the store's 256 KB limit are rejected before anything is written.

## Running the tests

```
cd scripts/dev-copy
python3 -m unittest test_dev_copy -v
```

## Status

Tested offline against synthetic exports and against a real export of the Weekly Trading Dashboard (85 datasets). The Claude-side steps (create the dashboard, copy data files, write batches) follow the documented behaviour of the Artifact tools but had not been run end to end when this was written. The first live run should be done with the dashboard owner watching, and any differences from this procedure (particularly how asset copy results identify each file) fixed here.
