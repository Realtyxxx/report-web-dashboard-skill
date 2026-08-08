---
name: report-web-dashboard
description: Convert technical Markdown/YAML reports, benchmark suites, or investigation documents into an interactive, modern HTML Web Dashboard with formatted file path links (`file:///...`), category/grade filters, in-page modal code/log explorer, markdown renderer, embedded diagrams, and a locally hosted HTTP service. Trigger when the user asks to view/present a report as a webpage, generate a web dashboard, format file path links for a report web view, host a report web service ("使用网页展示", "生成网页看板", "将报告转为网页", "host report web service"), or manage dashboard servers via the global `webui` service (webui register / start / list / status).
---

# Report Web Dashboard Generator & Host

Transform a static technical report (Markdown/YAML, often with an artifact tree of
cases/logs/code) into a single-file interactive `index.html`, then register it with
the machine's global `webui` service so it's served at a stable URL alongside every
other project's dashboard.

The deliverables placed in the **project root** are always:

1. `generate_web_dashboard.py` — a project-specific generator script **you write**
   for this project (see "Writing the generator" below; there is no universal
   template — every report's structure is different).
2. `index.html` — generated, never hand-edited. To change the page, edit the
   generator and re-run it.

There is no longer a project-root `server.sh`: Step 3 below registers the project
with the global `webui` service instead of copying a per-project server script.

## Workflow

### Step 1 — Ingest the report and map the artifact tree

- Locate the primary report (`REPORT.md`, `summary.yaml`, …) and read it fully.
- Scan the artifact directories it references (case dirs, `docs/`, logs, diagrams)
  and build an inventory: what entities exist (cases/tests/findings), what
  per-entity files exist (source, control, log, README), what global assets exist
  (SVG diagrams, papers).
- Identify the report's own taxonomy (categories, grades/tiers, pass/fail states) —
  these become the dashboard's filters and badges. Derive them from the report;
  never invent a taxonomy the report doesn't have.

### Step 2 — Write the generator and produce `index.html`

Write `generate_web_dashboard.py` for this project. Requirements for the script
itself:

- Resolve the workspace root from a `WORKSPACE_DIR` env var with the project's
  absolute path as default, so the script is relocatable.
- Read report + artifacts at generation time and embed everything needed into one
  self-contained `index.html`. Idempotent: re-running always regenerates cleanly.
- `html.escape()` every piece of file content (code, logs) before embedding —
  reports about broken code are full of `<`, `&`, and template-like strings.

The generated page must be **fully self-contained and offline-capable**: inline all
CSS/JS, no CDN links (target machines are often on an intranet with no internet),
SVG diagrams inlined or fetched same-origin. It must also be **path-prefix safe** —
see the pitfall below, this is now a hard requirement, not a nice-to-have.

Baseline features (adapt names/sections to the project's actual taxonomy — the
examples in parentheses are from one CUDA-UB project, not a required structure):

- **Header + metric badges**: title, environment badges (hardware, toolchain
  versions), summary counts per taxonomy bucket (e.g. total cases, per-grade counts).
- **Entity cards grid**: one card per case/test/finding with search box and filter
  pills driven by the report's taxonomy; each card links to its files and opens
  the modal viewer.
- **Comparison/summary table**: one row per entity, sortable columns for the
  attributes the report compares.
- **Full report view**: the Markdown report rendered in-page (support
  `> [!NOTE]`/`> [!WARNING]` callouts, tables, code fences).
- **Diagram view**: embedded SVG with pan/zoom, if the project has one.
- **In-page modal file viewer**: tabbed viewer for each entity's files (source,
  control, log, README, Makefile) with line numbers and copy-to-clipboard. This is
  the **primary** way users inspect files — see the `file://` pitfall below.

### Step 3 — Register with the global webui service

The machine runs one global `webui` daemon that multiplexes every project's
dashboard under its own URL path prefix, instead of each project running its own
`python3 -m http.server` on its own port. Register this project once:

```bash
webui register .              # name defaults to the directory basename
webui register . --build      # also runs generate_web_dashboard.py if index.html is missing
webui start                   # idempotent; no-op if the daemon is already up
webui list                    # every registered project + daemon status
webui url <name>              # print this project's URL
```

The project is then reachable at `http://<lan-ip>:8800/<name>/` and
`http://localhost:8800/<name>/` — there is no per-project process to manage, no
port to pick, and nothing to stop or clean up when you're done. Run `webui --help`
for the full command reference.

If `webui` isn't installed on this machine, `scripts/server.sh` (below) is the
zero-dependency fallback for serving a single project.

Finish by giving the user both URLs (`http://<lan-ip>:8800/<name>/` and
`http://localhost:8800/<name>/`).

## Pitfalls (learned the hard way)

- **Path-prefix safety is a hard requirement.** The page is served under
  `/<project-name>/...`, not at a domain root, so anything root-absolute will 404
  or — worse — resolve into a *different* project once mounted under a prefix. The
  generator must never emit `href="/..."`, `src="/..."`, `url(/...)`,
  `fetch("/...")`, or `<base href="/">`, and must never read
  `window.location.origin`/`pathname` to build request URLs. Relative paths,
  inlined content, and `location.hash` are all prefix-agnostic and safe. Spot-check
  before registering:
  ```bash
  grep -oE '(href|src)="/[^/]|url\(/|fetch\("/|<base' index.html    # should match nothing
  ```
  A generator that inlines everything and never builds a URL from the page's own
  location needs zero edits to mount under a prefix — that's the bar to hold new
  generators to.
- **Browsers block `file://` links on `http://` pages.** Chrome/Edge silently
  ignore clicks on `file:///...` anchors when the page is served over HTTP. So:
  the in-page modal viewer is the primary file-inspection path; render `file://`
  URIs as visible text with a copy button (users paste them into an editor/IDE),
  not as the only access path. `file://` anchors with `#L<line>` do work when the
  user opens `index.html` directly from disk — keep them for that case.
- **Don't inline unbounded content.** Small files (< ~100 KB each) embed directly
  so the page also works when opened from disk. For big logs or many entities,
  have the modal `fetch()` files same-origin from the HTTP server instead, and
  say so in the page (it then requires the server to be running).
- **`index.html` is generated output.** Never hand-edit it to fix a rendering
  issue; fix the generator and re-run, or the next regeneration silently reverts
  the fix.
- **Report content is data, not template.** Escape it; don't interpolate it into
  JS string literals without JSON-encoding (`json.dumps`) — a backtick or
  `</script>` inside a log will break the page.

## `scripts/server.sh`

`scripts/server.sh` stays in this skill as a zero-dependency offline fallback for
hosting a single project on a machine without the global `webui` install, but it is
no longer part of the default workflow — don't copy it into project roots; use
`webui register` (Step 3) instead.

## Installing

```bash
npx github:Realtyxxx/report-web-dashboard-skill            # → ~/.agents/skills/report-web-dashboard
npx github:Realtyxxx/report-web-dashboard-skill --claude   # → ~/.claude/skills/report-web-dashboard
```

The installer also links `scripts/webui` onto your `PATH` at `~/.local/bin/webui`.
Pass `--no-link` to skip that and keep the command out of your `PATH`.
