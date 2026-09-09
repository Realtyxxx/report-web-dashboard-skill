# report-web-dashboard

An agent skill that turns a technical report — plus the artifact tree around it
(cases, logs, source, diagrams) — into **one self-contained interactive
`index.html`**, and `webui`, a small global HTTP daemon that mounts every
project's dashboard under its own URL path prefix on a single port.

```bash
npx github:Realtyxxx/report-web-dashboard-skill
```

## What you get

**The skill** teaches an agent to write a project-specific
`generate_web_dashboard.py` that inlines everything — report, per-case source,
logs, READMEs, SVG diagrams — into a single offline-capable page with search,
taxonomy filters, a sortable comparison table, and an in-page modal file viewer.
No CDN, no build step, no external assets: the page works on an air-gapped
intranet and works when opened straight off disk.

**`webui`** replaces the "every project runs its own `python3 -m http.server` on
its own port" pattern:

```bash
webui register .        # register this project (name defaults to the dir basename)
webui start             # one daemon, port 8800, idempotent
webui list              # every registered dashboard + daemon status
webui url my-project    # → http://<lan-ip>:8800/my-project/
```

One daemon, one port, N dashboards:

```text
http://host:8800/                    # index of everything registered
http://host:8800/project-a/          # project A's dashboard
http://host:8800/project-b/          # project B's dashboard
```

The registry is a plain TSV at `~/.config/webui/registry.tsv` that hot-reloads on
every request — `webui register` takes effect with no restart.

## Install

```bash
npx github:Realtyxxx/report-web-dashboard-skill              # → ~/.agents/skills/report-web-dashboard
npx github:Realtyxxx/report-web-dashboard-skill --claude     # → ~/.claude/skills/report-web-dashboard
npx github:Realtyxxx/report-web-dashboard-skill --dir <path> # → <path>/report-web-dashboard
npx github:Realtyxxx/report-web-dashboard-skill --force      # overwrite an existing skill install
npx github:Realtyxxx/report-web-dashboard-skill --force-link # take over an occupied ~/.local/bin/webui
npx github:Realtyxxx/report-web-dashboard-skill --no-link    # skip the PATH symlink entirely
npx github:Realtyxxx/report-web-dashboard-skill --no-completion # skip the Zsh completion link
npx github:Realtyxxx/report-web-dashboard-skill --completion-dir <path> # default: ~/.zsh/completion
```

The installer copies `skill/` into your skills directory and links
`scripts/webui` to `~/.local/bin/webui`. If something unrelated already owns that
name, it warns and leaves it alone — `--force` covers the skill directory only,
because reinstalling a skill is routine while taking over a command on someone's
`PATH` is not; that needs the separate `--force-link`. If a daemon is already
running an older build, the installer tells you to run `webui restart`.

The installer also links `completions/_webui` to `~/.zsh/completion/_webui`.
Zsh completion covers public subcommands, their options, project directories,
and registered names for `url`, `open`, and `unregister`. Names are read directly
from the registry on each completion, without starting the daemon or accessing
the network; `WEBUI_HOME` is respected. Bash and Fish completions are not bundled.

If `~/.zsh/completion` is already in `fpath` and `compinit` is enabled, open a
new terminal. To activate in the current initialized Zsh session:

```zsh
autoload -Uz _webui
compdef _webui webui
```

Otherwise, add the completion directory to `fpath` **before** the existing
`compinit` or Oh My Zsh initialization. For a shell without a completion setup:

```zsh
fpath=("$HOME/.zsh/completion" $fpath)
autoload -Uz compinit
compinit
```

The installer does not edit shell startup files. `--no-link` skips both command
and completion links; `--no-completion` skips only the completion link. Existing
unrelated completion files are preserved unless `--force-link` is explicit.
The `personal-skills` bulk installer copies skill assets only; run this package's
installer afterward with `--force` to create the command and completion links.

Requires Python 3.8+ (stdlib only — no pip packages) and Node 18+ for the
installer.

## `webui` reference

|                                                        |                                                                                               |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| `webui register [PATH] [--name N] [--build] [--force]` | register a project dir; `--build` runs `generate_web_dashboard.py` if `index.html` is missing |
| `webui unregister NAME` / `webui prune`                | remove one entry / drop entries whose dir vanished                                            |
| `webui list [--json]`                                  | registered dashboards + status (works with the daemon down)                                   |
| `webui start` / `stop` / `restart` / `status`          | daemon lifecycle; `status` is strictly read-only                                              |
| `webui run`                                            | foreground, Ctrl+C stops                                                                      |
| `webui url NAME` / `webui open NAME`                   | print / open the dashboard URL                                                                |

Routing: `/` lists everything · `/<name>` 301s to `/<name>/` · `/<name>/` serves
that project's `index.html` · `/<name>/<sub>` serves files beneath it. An
unregistered name, or one whose directory has since disappeared, returns 404.

State lives in `~/.local/state/webui/` (`webui.pid`, `webui.json`, and
`webui.log`, rotated at 5 MB × 3).

## Notes worth reading before you rely on it

- **Pages must be path-prefix safe.** Dashboards are served under `/<name>/`, not
  at a domain root, so a generator must never emit `href="/…"`, `src="/…"`,
  `fetch("/…")`, or `<base href="/">`, and must never build URLs from
  `window.location.origin`/`pathname`. Root-absolute references will 404 or, worse,
  resolve into a _different_ project. Relative paths, inlined content, and
  `location.hash` are all safe.
- **Symlinks under a registered root are not followed** — they return 404. This is
  deliberate: resolving them opened a TOCTOU race where a symlink swapped between
  the containment check and the file open leaked files from outside the root.
  Paths are now walked with `O_NOFOLLOW` and pinned by file descriptor.
- **No authentication, binds `0.0.0.0`.** It is a LAN convenience tool in the same
  spirit as `python3 -m http.server`, not something to expose to a hostile network.
  The index page and 404s show absolute local filesystem paths.
- **`start` will not silently move to another port.** If 8800 is taken by something
  else it errors out rather than drifting, so a dashboard is never quietly
  somewhere you didn't expect.
- **The daemon never runs your generator for you.** A registered directory with no
  `index.html` falls through to a plain file listing. Generation happens only via
  the explicit `webui register --build`, because one daemon now spans N projects.
- **No auto-restart.** The daemon is a plain background process; it does not
  survive a reboot. Re-run `webui start`, or wire up a systemd user unit.

## Layout

```text
skill/
  SKILL.md            the skill itself
  scripts/webui       the global multiplexing daemon + CLI (Python, stdlib only)
  scripts/server.sh   zero-dependency single-project fallback for machines without webui
  completions/_webui  bundled Zsh completion definition
bin/install.js        the npx installer
```

## License

MIT
