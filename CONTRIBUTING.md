# Contributing to analytics-dachshund

This repo is the source of truth for Analytics-managed Claude dashboards. The live dashboard is a build output: change the code here, get it reviewed, then promote it. Never edit a live dashboard directly.

The full process, including rollback and the release checklist, is in the Confluence page "Developing Claude Dashboards: The Development LifeCycle" (Analytics space). This file is the short version for anyone opening a branch or a pull request.

## Before you start

- Every change starts from a Jira ticket in the Data Analytics (DA) project. Put the ticket key in your branch name and pull request.
- You need read access to this repo and, to preview a change, edit access to the dashboard you are changing (see "Who can edit the live dashboard" below).
- Do not commit credentials, tokens, query results, generated HTML or exports, customer-level data or survey comment text. See `README.md` for what belongs here.

## Branching

1. Branch from an up-to-date `main`. Never commit to `main` directly.
2. Name the branch `<type>/<short-description>-<jira-key>`, in lowercase with hyphens:

   | Type | Use for | Example |
   | --- | --- | --- |
   | `feat/` | New tabs, metrics, dashboards or tooling | `feat/price-tab-competitor-view-da-222` |
   | `fix/` | Corrections to queries, definitions or the page | `fix/inventory-slob-definition-da-111` |
   | `docs/` | Documentation only | `docs/weekly-trading-runbook-da-333` |

3. Keep a branch to one change, scoped to one dashboard where possible. A change under `shared/` affects every dashboard, so keep it separate from dashboard-specific work.
4. Keep branches short-lived. Rebase or merge `main` into your branch before asking for review.
5. Commit messages use a short prefix and an imperative summary, for example `fix: correct SLOB definition for expired stock`. Reference the Jira key in the pull request rather than in every commit.

## Testing a change

A branch holds code, but you need a dashboard to see the result.

- Make a private dev copy of the production dashboard with the `scripts/dev-copy` tool (ask Claude to "make a dev copy of the `<dashboard name>` for branch `<branch>`").
- Develop and test in the dev copy, then save the real change to your branch. The dev copy is only a preview.
- Do not share the dev copy as if it were the real dashboard, and do not point any scheduled task at it.
- Delete the dev copy once the branch is merged.

## Pull requests

Open a pull request into `main` when the change is ready. The description must cover:

- what changed and why, with the DA ticket link;
- which dashboard, tab or datasets are affected;
- how the numbers were checked: the source you reconciled against (finance pack, Looker view or direct query) and the result;
- the comparison basis and 445 week for any figure that changed;
- a link to the dev copy so the reviewer can look at it;
- whether any query's output columns changed, because the page can show gaps until the next refresh.

### Review rules

- At least one approval is required, and the author cannot approve their own pull request.
- The owner of the dashboard being changed must approve changes to that dashboard. Changes under `shared/` need review from the Analytics team.
- Any change to a metric definition, comparison basis or query logic needs a second pair of eyes on the logic, not just the layout.
- Changes to code that runs unattended need the dashboard owner's explicit sign-off. This covers refresh helper code, runbooks, scheduled-task instructions and anything under `skill/` or `src/`. Say so plainly in the pull request.
- Reviewers check, in order: metric logic and definitions, SQL correctness and cost, anything touching customer data, then layout.
- Review comments are resolved before merging. Merge with a squash or merge commit once approved; do not force-push over `main`.

## After merge

Merging approves a change but does not publish it. On merge, `.github/workflows/tag.yml` tags each changed dashboard automatically (`<dashboard>/<date>-<short commit>`). Nobody tags by hand.

The dashboard owner then promotes the tagged release to the live dashboard using the `scripts/promote` tool, then verifies the result and deletes the dev copy. Promotion is a separate, deliberate step and is not run during a refresh window.

## Who can edit the live dashboard

Edit access to a production dashboard is limited to the dashboard owner and members of the Analytics team. 

If a user is not listed, they can contribute: develop on a branch, open a pull request, and ask the owner to promote the merged release. If a problem is noticed on a live dashboard, raise it with the owner rather than fixing it live. A live-only edit is blocked by the promote tool and must be copied into the repo before the next release.

## Adding a dashboard

Follow "Adding a dashboard" in `README.md`: a lowercase, hyphenated folder under `dashboards/`, a README stating purpose, owner, audience, data sources, refresh schedule, live link and who holds edit access, and an entry in the dashboards table.

## Rolling back

Promote the previous release tag using the same tool. Data files are never part of a release, so nothing else needs undoing. Fix the problem on a new branch through this process.
