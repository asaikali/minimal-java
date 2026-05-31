# Renovate

This repo uses [Renovate](https://docs.renovatebot.com/) to keep dependencies
current. The setup is **self-hosted** — Renovate runs on GitHub-hosted Actions
runners under our control, not on Mend's SaaS. This document explains how the
pieces fit together, the architectural choices behind them, and how to use the
system day to day.

For inline detail on any specific decision, the workflow file
[`.github/workflows/renovate.yml`](../.github/workflows/renovate.yml) and the
config file [`renovate.json`](../renovate.json) carry the short version next to
the code.

## Architecture at a glance

```
┌─────────────────────────────────────────────────────┐
│  GitHub Actions (.github/workflows/renovate.yml)     │
│                                                      │
│   • Daily at 01:00 UTC                               │
│   • Plus on-demand via workflow_dispatch             │
│   • Authenticates with the built-in GITHUB_TOKEN     │
│   • Runs the renovatebot/github-action               │
└─────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│  This repository                                     │
│                                                      │
│   • Reads renovate.json for config                  │
│   • Scans Maven, Dockerfile, GitHub Actions deps    │
│   • Opens PRs for new versions                      │
│   • Maintains the Dependency Dashboard issue       │
└─────────────────────────────────────────────────────┘
```

## What Renovate updates here

Renovate auto-detects most of this repo's dependencies; one (chisel) needs a
small annotation. What's in scope:

- **Maven** (`pom.xml`) — the Spring Boot parent version and any declared
  dependencies. Versions are pinned in `pom.xml` (there's no separate lockfile),
  so a bump edits `pom.xml` directly.
- **Maven wrapper** (`.mvn/wrapper/maven-wrapper.properties`) — the wrapper and
  the Maven distribution it downloads.
- **Docker base images** (`Dockerfile`) — `ubuntu:${UBUNTU_VERSION}` and
  `eclipse-temurin:${JAVA_VERSION}-*`. Renovate's built-in Docker manager reads
  the `ARG` defaults that feed those `FROM` tags and bumps them there.
- **chisel** (`Dockerfile`) — fetched from a GitHub *release* URL, not referenced
  as an image tag, so the Docker manager can't see it. A `# renovate:` annotation
  above the `CHISEL_VERSION` ARG plus a `customManagers` entry in `renovate.json`
  track it via the `github-releases` datasource.
- **GitHub Actions** (`.github/workflows/*.yml`) — the actions pinned in the
  Renovate workflow itself (`actions/checkout`, `renovatebot/github-action`), and
  any others you add later. Note: updating these requires a GitHub App token (see
  "Upgrading to a GitHub App"); the built-in GITHUB_TOKEN can't write to workflow
  files.

> The JDK version appears in two independent places: `<java.version>` in `pom.xml`
> (the compiler release) and `JAVA_VERSION` in the `Dockerfile` (the runtime JRE).
> Renovate bumps the Dockerfile's `eclipse-temurin` tag; it does **not** rewrite
> the `pom.xml` property. Keep them in step by hand when you move major JDKs.

## Architectural decisions and why

These are the non-default choices in our setup. Each is a deliberate trade-off.

### Self-hosted, not Mend SaaS

The default way to use Renovate is to install the Mend-hosted GitHub App. Running
Renovate ourselves on GitHub-hosted Actions runners keeps everything inside
GitHub's boundary and under our control — no third-party SaaS clones the repo to
scan it, and the whole pipeline is visible in this repo.

For a fully public repo like this one, the Mend-hosted App is also a fine choice
(no workflow, no secrets to manage) and equally functional. This setup mirrors
the self-hosted approach used across these templates for consistency.

### Built-in GITHUB_TOKEN, not an App or a PAT

The workflow authenticates with `${{ secrets.GITHUB_TOKEN }}` — the token GitHub
mints automatically for every workflow run. No GitHub App, no Personal Access
Token, no repository secrets to create or rotate. For a single public repo with
no CI, this is the simplest setup that works, and it keeps the whole pipeline
self-contained.

The only repo-side requirement is one toggle (see [Setup](#setup)): GITHUB_TOKEN
may open PRs only when *Allow GitHub Actions to create and approve pull requests*
is enabled.

This trades away two things, both acceptable here:

1. **PRs opened with GITHUB_TOKEN don't trigger other workflows** — GitHub's
   recursion guard (without it, a workflow opening a PR could trigger another that
   opens another, forever). There's no CI in this repo to trigger yet (see
   [A note on CI](#a-note-on-ci)); if you add some and want a green check on
   Renovate PRs, move to a GitHub App (see
   [Upgrading to a GitHub App](#upgrading-to-a-github-app)).
2. **GITHUB_TOKEN can't be granted the `workflows` scope**, so Renovate won't bump
   the action versions pinned in `.github/workflows/`. The same App upgrade fixes
   that.

### Major-version bumps gated behind dashboard approval

Default Renovate behavior is to open a PR for *every* available update, including
majors. We gate major bumps behind a Dependency Dashboard checkbox:

```json
"packageRules": [
  {
    "matchUpdateTypes": ["major"],
    "dependencyDashboardApproval": true
  }
]
```

Patches and minors flow as PRs unchanged. Majors land on the Dependency Dashboard
issue under "Pending Approval" with a checkbox. Tick the box, run Renovate, and
*then* it opens the PR. The intent is to keep the review queue free of
breaking-change PRs that demand real decisions — those should be intentional, not
background noise.

### PR limits

```json
"prHourlyLimit": 0,
"prConcurrentLimit": 10
```

- **`prHourlyLimit: 0`** disables the rolling 1-hour throttle.
  `config:recommended` defaults to 2/hour, designed for shared-tenancy bots that
  risk drowning maintainers in notifications. For a single-repo, single-reviewer
  setup with a daily schedule plus on-demand runs, the throttle just slows the
  daily run from doing the work it already evaluated. Everything beyond the first
  two updates piles up in the dashboard's Rate-Limited section.
- **`prConcurrentLimit: 10`** is the cognitive cap. Above 10 open Renovate PRs the
  review queue stops being manageable. This is also the `config:recommended`
  default; we set it explicitly to signal intent.

## A note on CI

There's no automatic green check on Renovate PRs the way a CI-equipped repo would
have, because **this repo doesn't yet ship a build/test CI workflow**. The point
of an upgrade PR is that CI runs on it automatically, so a green check confirms
the upgrade is safe. Until you add a workflow (e.g. one running `./mvnw verify`,
and ideally a `docker buildx build` of the image series), review and test Renovate
PRs manually — build and run locally with the [`scripts/`](../scripts) helpers
before merging. Adding CI also means revisiting auth: PRs opened by GITHUB_TOKEN
don't trigger other workflows, so to get a green check on Renovate PRs you'd
switch to a GitHub App (see [Upgrading to a GitHub App](#upgrading-to-a-github-app)).

## The Dependency Dashboard

The single load-bearing UI of this setup is the Dependency Dashboard issue
(auto-created and auto-maintained by Renovate, titled "Dependency Dashboard").
Every Renovate run rewrites its body in place.

### How it works

The dashboard is a Markdown issue body containing GitHub-flavored task lists.
Each `- [ ]` checkbox is encoded with a hidden HTML comment that Renovate parses
on its next run. Clicking a checkbox edits one character of the issue body (the
space → `x`); on the next Renovate run, that flip becomes an instruction.

**Important:** clicking a checkbox does not trigger Renovate. The workflow runs on
a schedule (daily at 01:00 UTC) and on `workflow_dispatch`. After ticking a box,
Renovate sees the flipped state at the start of its next run. To make the click
take effect immediately, dispatch the workflow yourself with the
[`run-renovate.sh`](../scripts/run-renovate.sh) helper or the "Run workflow"
button in the Actions tab.

### Sections you'll see

1. **Pending Approval** — major-version bumps held back by our
   `dependencyDashboardApproval: true` rule. Tick a box to opt into a PR for that
   bump on the next run.
2. **Rate-Limited** — updates Renovate evaluated but didn't open PRs for, due to
   `prHourlyLimit` or `prConcurrentLimit`. With our settings (hourly limit
   disabled, concurrent limit 10), this section appears only when 10+ Renovate PRs
   are already open. Tick to bypass the limit for a specific update.
3. **Open** — links to existing Renovate PRs. Tick to force a rebase (useful after
   merging a conflicting PR).
4. **Detected Dependencies** — informational inventory of every dependency
   Renovate found. Useful for confirming what's in scope (e.g. that the chisel
   custom manager is matching).

There's also a "🔐 Create all rate-limited PRs at once" master checkbox that acts
on every entry in a section — useful for draining backlogs.

### Closing the dashboard issue

Don't bother — Renovate reopens it on the next run. To suppress the dashboard
entirely, set `"dependencyDashboard": false` in `renovate.json`. Closing without
that config change is at most a few-hour reprieve.

## Pull request shapes you'll see

Knowing which file a PR touches makes review faster.

1. **Maven dependency / parent bumps** — edit `pom.xml` (and, for the wrapper,
   `.mvn/wrapper/maven-wrapper.properties`). The version is pinned in the file, so
   the diff shows the old → new version directly.
2. **Docker base-image bumps** — edit the `ubuntu`/`eclipse-temurin` `ARG` default
   in the `Dockerfile`. Rebuild the image series locally
   ([`scripts/build-images.sh`](../scripts/build-images.sh)) before merging.
3. **chisel bumps** — edit the `CHISEL_VERSION` `ARG`, driven by the custom
   manager. Same "rebuild to verify" applies.
4. **GitHub Actions bumps** — edit the pinned action versions in
   `.github/workflows/`.
5. **Major bumps** — don't appear as PRs by default; they're parked on the
   Dependency Dashboard with a checkbox until you opt in. After ticking the box
   and running Renovate, the resulting PR is one of the shapes above. These are
   the "real decision" category — read the release notes (Renovate links them in
   the PR body) before merging.

## Day-to-day usage

### Triggering a Renovate run

Three ways:

1. **Wait** for the daily 01:00 UTC scheduled run.
2. **`run-renovate.sh`** — from anywhere in the repo (mise adds `scripts/` to your
   PATH, so `run-renovate.sh`; otherwise `./scripts/run-renovate.sh`). Dispatches
   the workflow on GitHub and tails its logs.
3. **GitHub UI**: Actions tab → Renovate → Run workflow.

Use the manual trigger after ticking a Dependency Dashboard checkbox, or after
merging a PR that conflicts with several other open Renovate PRs (so the rebases
happen now, not at 01:00 UTC).

### Previewing locally without touching GitHub

[`scripts/renovate.sh`](../scripts/renovate.sh) (also on PATH via mise) runs
Renovate against your working tree in `--dry-run=full --platform=local` mode. It
prints what Renovate *would* propose without opening any PRs or modifying any
files.

```
renovate.sh
```

Useful for tuning `renovate.json` before committing — in particular for confirming
the chisel custom manager matches (it should show a `canonical/chisel` update when
a newer release exists). The trailing summary lists every PR Renovate would open.
Ignore "Error updating branch" warnings — those are the local platform's expected
limitation, not real failures.

### Reviewing a Renovate PR

1. **Build it.** Until this repo has CI (see "A note on CI"), this is the
   load-bearing signal. For Maven bumps run `./mvnw verify`; for Docker/chisel
   bumps run [`scripts/build-images.sh`](../scripts/build-images.sh) and a quick
   [`scripts/run-app.sh`](../scripts/run-app.sh) + `curl`.
2. **Read the release notes.** Renovate links them in the PR body. For
   patches/minors they're usually bug fixes — skim. For majors, read carefully.
3. **Look at the diff.** Confirm the changed version matches what the title says,
   and that nothing unexpected was touched.

If multiple Renovate PRs are open, merging one will conflict with the others.
Renovate auto-rebases the rest on its next run; with `run-renovate.sh` you can
force the rebase immediately rather than waiting for the schedule.

## Setup

There are no secrets to configure. The only requirement is one repo toggle so the
built-in GITHUB_TOKEN is allowed to open PRs:

> Settings → Actions → General → Workflow permissions →
> enable **"Allow GitHub Actions to create and approve pull requests"**.

With that enabled, the daily schedule (or a manual `run-renovate.sh`) opens PRs
and maintains the Dependency Dashboard. Without it, the workflow run still
*succeeds* but PR creation is refused — that's the first thing to check if runs
finish but nothing appears.

### Upgrading to a GitHub App

Switch to a GitHub App when you want CI to run on Renovate PRs (PRs opened by
GITHUB_TOKEN don't trigger other workflows), want Renovate to update the action
versions in `.github/workflows/`, or want to drive many repos from one identity.
An App is org- or personal-owned and mints short-lived per-run tokens. Steps:

1. **Create a GitHub App** with these repository permissions:
   - Contents: Read and write
   - Pull requests: Read and write
   - Issues: Read and write
   - Workflows: Read and write
   - Metadata: Read (granted automatically)
2. **Generate a private key** for the App and download the PEM file.
3. **Install the App** on this repository (you create the App and key *once* and
   reuse them across every repo; the install can target "All repositories").
4. **Add two repository secrets**: `RENOVATE_APP_ID` (numeric App ID) and
   `RENOVATE_APP_PRIVATE_KEY` (full PEM contents).
5. **In the workflow**, mint a token from those secrets and pass it to Renovate
   instead of GITHUB_TOKEN:

   ```yaml
   - name: Generate GitHub App installation token
     id: app-token
     uses: actions/create-github-app-token@v3
     with:
       app-id: ${{ secrets.RENOVATE_APP_ID }}
       private-key: ${{ secrets.RENOVATE_APP_PRIVATE_KEY }}
   # ...then in the Renovate step: token: ${{ steps.app-token.outputs.token }}
   ```

On a **personal account there are no account-wide Actions secrets**, so the two
secrets live per-repo (the App and key themselves are still created only once); an
org can set them once as org secrets. To drive many repos from one place without
repeating secrets, run the App-authenticated workflow from a single "runner" repo
and set `RENOVATE_REPOSITORIES` to the list (or let it autodiscover).

## Troubleshooting

### The workflow runs but no PRs open

Check the Dependency Dashboard issue. The most common causes are visible there:

- Updates under "Pending Approval" are gated by our major-bump rule — tick a
  checkbox to opt in.
- Updates under "Rate-Limited" hit `prConcurrentLimit` (10 PRs). Merge or close
  some open Renovate PRs first.

If there's no dashboard issue and no PRs at all, the most likely cause is the repo
toggle — *Allow GitHub Actions to create and approve pull requests* is off (see
[Setup](#setup)). Otherwise check the workflow run logs.

### chisel (or the base images) isn't being updated

Run `scripts/renovate.sh` and check the "Detected Dependencies" output / log for a
`canonical/chisel` entry. If it's missing, the `# renovate:` annotation in the
`Dockerfile` and the `customManagers` regex in `renovate.json` have drifted apart —
the comment must sit on the line *immediately above* the `ARG CHISEL_VERSION=…`
line for the regex to match. For the base images, confirm the `ARG` defaults still
feed the `FROM` tags (`ubuntu:${UBUNTU_VERSION}`, `eclipse-temurin:${JAVA_VERSION}-*`).

### A Renovate PR I closed keeps reappearing

By default Renovate respects "user closed this" and doesn't reopen. But if the
underlying branch wasn't deleted, some configurations can cause Renovate to retry.
Always close with:

```
gh pr close <number> --delete-branch
```

Renovate then sees "user rejected this update" and only re-proposes it under
different configuration (e.g. a different version later).

### A major-bump PR is open even though we configured dashboard approval

Configuration changes to `renovate.json` apply to *future* update decisions, not
retroactively. PRs opened before the rule existed stay open until you close them
manually (with `--delete-branch`); on the next run the major is re-evaluated under
the new rule and surfaces as a dashboard checkbox instead.

### The workflow says "No repositories found" and exits

The action needs `RENOVATE_REPOSITORIES` set in the workflow's env block. We set
it to `${{ github.repository }}`. If the env is missing or empty, the action
defaults to scanning whatever the token can see, which for an App-installation
token returns no repositories.

## See also

- The header of [`.github/workflows/renovate.yml`](../.github/workflows/renovate.yml)
  explains the workflow's structure and the auth / PR-permission setup inline.
- [`renovate.json`](../renovate.json) has inline `description` fields on each
  rule — quick context without leaving the file.
- [Renovate's own documentation](https://docs.renovatebot.com/) is comprehensive;
  this doc covers our *opinions*, not Renovate's full feature surface.
