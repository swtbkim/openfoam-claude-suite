# OpenFOAM CFD Suite for Claude Code

Natural-language OpenFOAM v2412 automation as a Claude Code plugin. You say
"simulate air flow over a backward-facing step at 10 m/s"; the suite parses it
into a spec, picks a solver and tutorial template, builds the mesh, configures
the case, runs it (serial or MPI-parallel, backgrounded if long), verifies the
result, and writes a report with plots and numbers.

Four skills:

- **of-sim** - the pipeline: spec -> solver/template selection -> mesh
  (template, parametric blockMesh, or STL + snappyHexMesh; optional FreeCAD
  MCP for geometry from scratch) -> case configuration -> dict dry-run ->
  run -> verify -> report. Every phase has a verification gate (checkMesh
  "Mesh OK" + bounding-box check, dict dry-run, convergence verdict,
  continuity error, field boundedness, y+, quantity-of-interest stability).
  A failed gate triggers a bounded remediation ladder, then honest escalation.
- **of-post** - residual/convergence plots, forces and force coefficients,
  y+, min/max, flow rates, line samples, probes, VTK export for ParaView,
  screenshots, results report. Also monitors running cases.
- **of-doctor** - failure diagnosis via a signature-matched taxonomy
  (FOAM FATAL classes, divergence, bounding spam, MPI/decomposition errors,
  mesh-quality failures) plus a divergence deep-dive: root cause in one
  sentence, minimal fix as an exact dict diff, optional rerun.
- **of-setup** - one-time machine probe that generates the machine layer
  (see First run below).

The suite is self-improving (pipeline phase P8): after each completed
analysis it back-injects session lessons - invocation pitfalls into SKILL.md,
reusable CFD knowledge into the lazy-loaded references, failure signatures
into the of-doctor taxonomy - and commits them. This loop works best on the
git-clone install, where edits persist and are version-controlled.

## Requirements

- Claude Code on Windows (with a WSL distro that has OpenFOAM) or on Linux.
- OpenFOAM v2412 - source build or openfoam.com packages.
- git, gnuplot (residual plots).
- Optional: paraview/pvbatch (screenshots), FreeCAD MCP server (geometry
  creation from scratch).

## Install

### Route 1 (recommended): git clone, editable and self-improving

```
git clone https://github.com/swtbkim/openfoam-claude-suite ~/.claude/skills/openfoam-claude-suite
```

(Windows: clone to `C:/Users/<you>/.claude/skills/openfoam-claude-suite`.)

The clone contains `.claude-plugin/plugin.json`, so Claude Code treats it as
a skills-dir plugin and loads it automatically. Skills are invoked as
`/openfoam:of-sim`, `/openfoam:of-post`, `/openfoam:of-doctor`,
`/openfoam:of-setup`. Because the install is a plain git checkout, the P8
loop can edit and commit skill improvements, and `git pull` updates cleanly
(the machine layer is gitignored and untouched). One caveat on Windows+WSL:
the `allowed-tools` frontmatter `/of-setup` adds lives in tracked SKILL.md
files - if `git pull` conflicts there, take the upstream version and re-run
`/of-setup`.

Copying the four `skills/*` folders directly into `~/.claude/skills/` also
works (skills load un-namespaced as `/of-sim`, `/of-setup`, ...), but you
lose the `/openfoam:` namespace, `git pull` updates, and the P8
self-improvement commits - prefer the clone.

### Route 2: plugin marketplace

```
claude plugin marketplace add swtbkim/openfoam-claude-suite
claude plugin install openfoam@openfoam-claude-suite
```

Caveat: the plugin cache is replaced on update, which wipes the in-plugin
generated file (`environment.md`), the `allowed-tools` frontmatter patch,
and any P8 self-edits. `of-env.sh` (in `~/.config/openfoam-claude-suite/`)
and the case registry (in `$FOAM_RUN`) live outside the plugin and survive.
Re-run `/of-setup` after every update; prefer route 1 if you want the
self-improvement loop.

## First run: /of-setup

Run `/of-setup` once per machine. It probes and writes the machine layer:

- Detects the host mode (Windows + WSL vs native Linux), the distro, user,
  core count, and RAM.
- Locates the OpenFOAM install (`/opt/OpenFOAM-*/etc/bashrc` or
  `/usr/lib/openfoam/openfoam*/etc/bashrc`), FOAM_RUN, the tutorials tree,
  any user-built solvers, and extras (mpirun, gnuplot, pvpython).
- Writes `~/.config/openfoam-claude-suite/of-env.sh` (inside the distro /
  Linux home; survives plugin updates) - two lines: `OF_BASHRC=<path to
  etc/bashrc>` (required) and optionally `OF_NPROC_CAP=<max parallel ranks>`.
- Writes `skills/of-sim/references/environment.md` - the machine-facts table
  the skills read instead of hardcoding paths.
- Adds the machine-specific `allowed-tools` frontmatter to the SKILL.md
  files (the distribution ships without it, since it names your distro).
- Creates `$FOAM_RUN/case-registry.md` if missing.

`environment.md` is gitignored and `of-env.sh` lives outside the repo;
`scripts/of-env.example.sh` and `references/environment.example.md` show
what they look like when filled in.

## Usage

```
> simulate laminar channel flow of water at Re 500 and plot the developed velocity profile
> VOF dam break with an obstacle, 1 s, output frames every 0.02 s
> my simpleFoam run in $FOAM_RUN/diffuser-2026-07-08 diverged - why?
```

The first two route to of-sim (add `--auto` to skip clarifying questions and
take engineering defaults), the third to of-doctor. Interactive mode asks at
most one batch of targeted questions, echoes the completed spec, and confirms
before any run expected to exceed ~10 min.

## Validation (2026-06 build, OpenFOAM v2412)

- Lid-driven cavity, Re=100, vs Ghia et al. benchmark: max centerline
  velocity error 0.49%.
- pitzDaily backward-facing step (simpleFoam, kEpsilon): mass balance closes
  to 5e-11; reattachment length x/h = 7.08.
- motorBike: snappyHexMesh 355k cells, 8-rank simpleFoam, Cd = 0.419,
  2.5 min wall clock end to end.

The `skills/of-sim/scripts/val-*` regression harness reproduces these.

## Architecture

```
openfoam-claude-suite/
  .claude-plugin/plugin.json        plugin manifest
  skills/
    of-setup/SKILL.md               machine probe; generates the machine layer
    of-sim/
      SKILL.md                      pipeline P0-P8, invocation rules, gates
      references/                   solvers.md, templates.md, meshing.md,
                                    case-anatomy.md, numerics.md (lazy-loaded)
      references/environment.example.md   example generated machine-facts doc
      scripts/                      ofrun.sh, ofcase.sh, ofmon.sh wrappers
                                    + val-* regression harness
      scripts/of-env.example.sh     example generated env config
    of-post/SKILL.md                results extraction, plots, report
    of-doctor/SKILL.md              failure taxonomy + divergence deep-dive
```

### The machine layer

Everything machine-specific lives in three generated files, never in the
repo:

- `~/.config/openfoam-claude-suite/of-env.sh` - shell config with
  `OF_BASHRC` (and optionally `OF_NPROC_CAP`); written there by `/of-setup`
  so it survives plugin updates. Wrappers resolve it in order:
  `$OF_SUITE_ENV` if set -> `of-env.sh` next to the wrapper (optional manual
  override) -> `~/.config/openfoam-claude-suite/of-env.sh` -> autodetect the
  newest of `/opt/OpenFOAM-*/etc/bashrc` and
  `/usr/lib/openfoam/openfoam*/etc/bashrc`.
- `skills/of-sim/references/environment.md` - the machine-facts doc.
- `$FOAM_RUN/case-registry.md` - one line per case (date, path, solver,
  cells, verdict, result). It lives beside the cases, not in the plugin, so
  it survives plugin updates and reinstalls.

The first two are gitignored so that neither `git pull` nor a marketplace
update can clobber your machine configuration.

### Wrappers and the __OFRC sentinel

All OpenFOAM commands go through three wrappers: `ofrun.sh` (run/par/sh -
sources OF_BASHRC, executes in the case dir, logs to `log.<app>`),
`ofcase.sh` (new/set/get/info/clean - tutorial cloning and foamDictionary
edits), and `ofmon.sh` (status/residuals/plot/errors - reduces a solver log
to a verdict: CONVERGED | COMPLETED_ENDTIME | RUNNING_OK | DIVERGED | FATAL
| NO_LOG). Each wrapper prints `__OFRC=<rc>__` as its last line; the agent
parses that sentinel instead of the process exit code, because on Windows
`wsl.exe` exit codes are unreliable through the MSYS layer. On Windows the
wrappers are invoked via `wsl.exe -d <distro> --exec bash ...` and case
dicts are authored through the `\\wsl.localhost\<distro>\...` UNC view; on
native Linux the wrappers run directly and the same sentinel and verdicts
apply.

## Safety

- The suite never modifies the OpenFOAM installation; it is treated as a
  read-only reference.
- All cases are created under `$FOAM_RUN`. Cases not created in the current
  session are never deleted without asking.
- Long runs: anything estimated over ~10 min needs confirmation in
  interactive mode; over ~1 h the suite presents a cheaper alternative
  (coarser mesh, shorter endTime, steady approximation) before starting, or
  picks it and says so under `--auto`.

## Contribution

Issue, PR

## License

MIT - see [LICENSE](LICENSE).
