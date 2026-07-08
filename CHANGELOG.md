# Changelog

## 0.1.0 (unreleased)

- Initial packaging of the OpenFOAM CFD suite as a Claude Code plugin:
  of-sim, of-post, of-doctor, plus new one-time /of-setup.
- Suite built and validated 2026-06 on OpenFOAM v2412 (Ghia Re=100 cavity,
  pitzDaily backward-facing step, motorBike snappyHexMesh regressions).
- Overhauled 2026-07: verification gates, failure taxonomy, wrapper
  hardening, P8 self-improvement retrospective loop.
- Machine specifics factored out into a generated, gitignored layer
  (~/.config/openfoam-claude-suite/of-env.sh + references/environment.md,
  written by /of-setup);
  shipped as *.example.* templates.
- Native Linux host mode added alongside the original Windows + WSL mode.
- Case registry moved to $FOAM_RUN/case-registry.md so it lives beside the
  cases and survives plugin updates.
