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
│   • Authenticates as a GitHub App                    │
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
- **Docker base images** (`images/**/Dockerfile`) — `ubuntu:${UBUNTU_VERSION}` (in
  `images/2-size/ubuntu/Dockerfile`) and `eclipse-temurin:${JAVA_VERSION}-*` (in the jre,
  fat, app, jvm-aot, and spring-aot Dockerfiles). Renovate's Docker manager scans
  every `Dockerfile` and *detects* these (it resolves the `${ARG}` to read the
  version) but **cannot rewrite an `${ARG}`-composed tag in place** — it looks for
  the literal `eclipse-temurin:25-jre`, which isn't in the file. So they're
  configured to **not** open patch/minor PRs (a `packageRules` entry in
  `renovate.json` disables those); only a new **major** surfaces on the Dependency
  Dashboard as a heads-up, and you bump `JAVA_VERSION` / `UBUNTU_VERSION` by hand to
  keep the tags clean. chisel is the exception — see below.
- **chisel** (`images/2-size/ubuntu/Dockerfile`) — fetched from a GitHub *release* URL, not referenced
  as an image tag, so the Docker manager can't see it. A `# renovate:` annotation
  above the `CHISEL_VERSION` ARG plus a `customManagers` entry in `renovate.json`
  track it via the `github-releases` datasource.
- **GitHub Actions** (`.github/workflows/*.yml`) — the actions pinned in the
  Renovate workflow itself (`actions/checkout`, `actions/create-github-app-token`,
  `renovatebot/github-action`), and any others you add later. Updating workflow
  files needs the App's `workflows: write` permission (see [Auth](#auth-a-github-app-not-github_token-or-a-pat)).

> The JDK version appears in two independent places: `<java.version>` in `pom.xml`
> (the compiler release) and `JAVA_VERSION` in the `images/**/Dockerfile` files (the
> runtime JRE). Renovate bumps the `eclipse-temurin` tag; it does **not** rewrite
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

### Auth: a GitHub App, not GITHUB_TOKEN or a PAT

Renovate has to authenticate to the GitHub API — it pushes branches, opens PRs,
and maintains the Dependency Dashboard issue. Self-hosting decides *where Renovate
runs* (our Actions runners); it doesn't remove the need for a credential. We
authenticate as a **GitHub App**, minting a short-lived installation token at
runtime with [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token).

We started with the built-in `GITHUB_TOKEN` because it needs no setup, then hit a
wall — which is the clearest argument for the App:

> **`GITHUB_TOKEN` cannot open pull requests** unless the repo enables *Settings →
> Actions → General → "Allow GitHub Actions to create and approve pull requests"*,
> which is **off by default**. With it off, the Renovate run reports *success* but
> opens nothing — every update just sits on the Dependency Dashboard, which looks
> like a silent failure. Turning it on also relaxes a repo-wide security setting
> for *all* Actions, not just Renovate.

A GitHub App installation token is a **different actor**, so it is **not subject to
that toggle** — Renovate opens PRs out of the box, and you leave the security
setting alone. Two more reasons the App wins as the repo grows:

1. **PRs opened by `GITHUB_TOKEN` don't trigger other workflows** — GitHub's
   recursion guard (without it, a workflow opening a PR could loop forever). So any
   CI you add (e.g. `./mvnw verify`) would never run on a Renovate PR, defeating the
   point of an auto-verified upgrade (see [A note on CI](#a-note-on-ci)). App-token
   PRs have a different actor, so CI triggers normally.
2. **`GITHUB_TOKEN` can't hold the `workflows` scope**, so it can't update the
   actions pinned in `.github/workflows/`. The App (Workflows: write) can.

And why an App rather than a **PAT**: a PAT is owned by an individual (it breaks
when that person leaves or rotates it) and is a long-lived broad-scope secret. An
App is owned by the account/org, scoped per-install, and its token expires in ~1
hour — the repo only stores the App ID and private key. See [Setup](#setup) for the
one-time configuration.

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

The CI gate is [`.github/workflows/build.yml`](../.github/workflows/build.yml),
which runs `./mvnw verify` (compile + test + package) on every push and pull
request. A green check there is the signal that an upgrade is safe, which is the
whole point of an auto-opened upgrade PR. It runs on Renovate's PRs automatically:
because Renovate authenticates as a GitHub App (not `GITHUB_TOKEN`), the PRs it
opens trigger other workflows normally (see [Auth](#auth-a-github-app-not-github_token-or-a-pat)).

`build.yml` intentionally does **not** build the Docker image series — that's a
multi-arch buildx job better run on demand with
[`scripts/build-images.sh`](../scripts/build-images.sh). So for Docker base-image
and chisel bumps, the green Maven check confirms the code still builds, but rebuild
the image locally before merging (see [Reviewing a Renovate PR](#reviewing-a-renovate-pr)).

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
2. **Docker base images (ubuntu / eclipse-temurin)** — *not* auto-PR'd (see
   [What Renovate updates here](#what-renovate-updates-here)): patch/minor updates
   are disabled because Renovate can't rewrite the `${ARG}`-composed tags, and a
   new major just appears on the dashboard. Bump `JAVA_VERSION` (in the runtime
   `images/**/Dockerfile` files) / `UBUNTU_VERSION` (in `images/2-size/ubuntu/Dockerfile`)
   by hand, then rebuild the series locally
   ([`scripts/build-images.sh`](../scripts/build-images.sh)) before committing.
3. **chisel bumps** — *these do* open PRs (the custom manager edits the
   `CHISEL_VERSION` ARG directly). Rebuild the series locally to verify before
   merging.
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

1. **Check the green check.** [`build.yml`](../.github/workflows/build.yml) runs
   `./mvnw verify` on the PR — the load-bearing signal that it still compiles and
   tests pass. CI doesn't build the Docker image, so for Docker base-image and
   chisel bumps also run [`scripts/build-images.sh`](../scripts/build-images.sh)
   and a quick [`scripts/run-app.sh`](../scripts/run-app.sh) + `curl` before merging.
2. **Read the release notes.** Renovate links them in the PR body. For
   patches/minors they're usually bug fixes — skim. For majors, read carefully.
3. **Look at the diff.** Confirm the changed version matches what the title says,
   and that nothing unexpected was touched.

If multiple Renovate PRs are open, merging one will conflict with the others.
Renovate auto-rebases the rest on its next run; with `run-renovate.sh` you can
force the rebase immediately rather than waiting for the schedule.

## Setup

Until the GitHub App is created, installed, and its two secrets exist, the workflow
runs on schedule but can't open PRs. One-time steps (the workflow header at
[`.github/workflows/renovate.yml`](../.github/workflows/renovate.yml) carries the
same list inline):

1. **Create a GitHub App.** Settings → Developer settings → GitHub Apps → *New
   GitHub App* (personal- or org-owned). Give it a name, leave the homepage URL as
   anything, **uncheck Webhook → Active** (Renovate polls; no callback needed), and
   grant these **repository permissions**:
   - Contents: Read and write — push branches and commits
   - Pull requests: Read and write — open and update PRs
   - Issues: Read and write — maintain the Dependency Dashboard issue
   - Workflows: Read and write — let Renovate update files in `.github/workflows/`
   - Metadata: Read — granted automatically
2. **Generate a private key** (App settings → *Generate a private key*) and
   download the PEM file.
3. **Install the App** on this repository (App page → *Install App* → choose the
   account → select this repo, or "All repositories"). You create the App and key
   **once** and reuse them across every repo; only the install list and the secrets
   are per-repo.
4. **Add two repository secrets** (repo → Settings → Secrets and variables →
   Actions → *New repository secret*):
   - `RENOVATE_APP_ID` — the App's numeric App ID (shown on the App settings page)
   - `RENOVATE_APP_PRIVATE_KEY` — the entire PEM contents, including the
     `-----BEGIN…` / `-----END…` lines

The workflow's first step mints an installation token from those secrets
(`actions/create-github-app-token`), and a pre-flight step then does one repo read
so a misinstalled App fails within a second with a clear error rather than after a
full scan. **No "Allow GitHub Actions to create and approve pull requests" toggle is
needed** — that setting only gates `GITHUB_TOKEN`, and the App token isn't subject
to it.

> **Secrets on a personal account.** There are no account-wide Actions secrets on a
> personal account, so the two secrets above live in each repo (the App and key are
> still created only once). An org can set them once as **org secrets**. To drive
> many repos from one place without repeating secrets, run the App-authenticated
> workflow from a single "runner" repo and set `RENOVATE_REPOSITORIES` to the list
> (or let it autodiscover).

## Troubleshooting

### The workflow runs but no PRs open

Check the Dependency Dashboard issue. The most common causes are visible there:

- Updates under "Pending Approval" are gated by our major-bump rule — tick a
  checkbox to opt in.
- Updates under "Rate-Limited" hit `prConcurrentLimit` (10 PRs). Merge or close
  some open Renovate PRs first.

If there's no dashboard issue and no PRs at all, check the workflow run logs. The
`Validate GitHub App token can access the repo` step fails fast with a clear error
if the App isn't installed on this repo. (Note: because Renovate authenticates as
a GitHub App, the *"Allow GitHub Actions to create and approve pull requests"*
toggle does **not** apply here — that one only gates `GITHUB_TOKEN`.)

### chisel isn't being updated

Run `scripts/renovate.sh` and check the "Detected Dependencies" output / log for a
`canonical/chisel` entry. If it's missing, the `# renovate:` annotation in
`images/2-size/ubuntu/Dockerfile` and the `customManagers` regex in `renovate.json` have
drifted apart — the comment must sit on the line *immediately above* the
`ARG CHISEL_VERSION=…` line for the regex to match.

### A base-image (ubuntu/temurin) update isn't opening a PR

That's by design, not a bug. Those tags are `${ARG}`-composed, which Renovate can
detect but not rewrite, so a `packageRules` entry disables their patch/minor PRs
(see [What Renovate updates here](#what-renovate-updates-here)). Only a new **major**
shows on the dashboard as a heads-up; bump `JAVA_VERSION` / `UBUNTU_VERSION` in the
`images/**/Dockerfile` files by hand. If you'd rather have Renovate pin and PR them, remove that
`packageRules` entry and add `# renovate:` annotations on the two ARGs like chisel's.

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
  explains the workflow's structure and the GitHub App setup inline.
- [`renovate.json`](../renovate.json) has inline `description` fields on each
  rule — quick context without leaving the file.
- [Renovate's own documentation](https://docs.renovatebot.com/) is comprehensive;
  this doc covers our *opinions*, not Renovate's full feature surface.
