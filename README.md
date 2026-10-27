# analytics-dachshund

The source code for Claude dashboards managed by the Pet Circle Analytics team.

Each dashboard is a Claude artifact that is refreshed from our data warehouse (BigQuery) and shared with the business. The artifacts themselves live in Claude; this repo holds everything needed to build, refresh and understand them, so that changes are reviewed, versioned and recoverable, and so the work doesn't depend on any one person's machine or session.

## What belongs here

- SQL queries that feed each dashboard
- Build and refresh scripts, and the page templates and styling
- Non-secret configuration, such as channel groupings, calendar logic and target definitions
- The Claude skills that drive each dashboard's scheduled refresh
- Documentation: what each dashboard shows, where its numbers come from, who owns it, and how it is refreshed

## What does not belong here

- Credentials, tokens or service account keys (use environment variables or a secrets manager)
- Query results or generated output, including exports and HTML snapshots
- Customer-level or otherwise sensitive data

## Layout

```
analytics-dachshund/
├── README.md
├── dashboards/
│   └── <dashboard-name>/      # one folder per dashboard
│       └── README.md          # purpose, owner, data sources, refresh cadence, artifact link
├── scripts/                   # repo tooling, e.g. scripts/dev-copy to make a private dev copy of a dashboard
├── shared/                    # logic reused by more than one dashboard (calendar, channel mapping, styling)
└── docs/                      # conventions and onboarding
```

Only `dashboards/` exists so far. `shared/` and `docs/` will be added when a second dashboard needs common logic or the conventions need writing down. Until then, keep each dashboard self-contained.

## Dashboards

| Dashboard | Purpose | Refresh |
| --- | --- | --- |
| [Weekly Trading](dashboards/weekly-trading/) | Weekly trading pack covering the whole business, from highlights through to operations | Monday 8am Sydney, with an Operations top-up on Tuesday |

## Adding a dashboard

1. Create `dashboards/<dashboard-name>/` using lowercase, hyphenated names.
2. Add a `README.md` stating the dashboard's purpose, owner, audience, data sources, refresh schedule and artifact link.
3. Keep queries, scripts and templates inside that folder. Move something to `shared/` only once a second dashboard needs it.
4. Add the dashboard to the table above.

## Conventions

- Work on a branch and raise a pull request into `main`. Changes to metric definitions deserve a second pair of eyes.
- Use Australian English and Pet Circle's reporting conventions (445 calendar, Sydney time) in documentation and output.
- State the 445 week and the comparison basis (last week, last year, budget) wherever a figure is shown.
