#!/bin/bash
# ofrun.sh - OpenFOAM execution wrapper for Claude Code automation.
#
# Runs inside Linux. <scripts> = this directory as seen from Linux.
# Mode A (Windows host + WSL; <scripts> like /mnt/c/Users/<you>/...):
#   MSYS_NO_PATHCONV=1 wsl.exe -d <distro> --exec bash <scripts>/ofrun.sh <subcommand> ...
# Mode B (native Linux):
#   bash <scripts>/ofrun.sh <subcommand> ...
#
# Subcommands:
#   env                            sanity-print environment, create FOAM_RUN
#   run <case> <app> [args...]     run app in case dir, log to log.<app>, tail
#   par <case> <N> <app> [args...] mpirun -np N app -parallel, log, tail
#                                  (N lowered to OF_NPROC_CAP if set and exceeded)
#   sh  <case|-> <command line...> eval a shell line in case dir (- = no cd)
#
# Last line of output is always: __OFRC=<exit-code>__
# (wsl.exe exit codes are unreliable through MSYS; parse the sentinel instead)

# --- resolve OpenFOAM env: OF_SUITE_ENV -> of-env.sh (see of-env.example.sh) -> autodetect ---
_sd=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for _e in "${OF_SUITE_ENV:-}" "$_sd/of-env.sh" "$HOME/.config/openfoam-claude-suite/of-env.sh"; do
    [ -n "$_e" ] && [ -f "$_e" ] && { . "$_e"; break; }
done
[ -n "${OF_BASHRC:-}" ] || OF_BASHRC=$(ls -t /opt/OpenFOAM-*/etc/bashrc /usr/lib/openfoam/openfoam*/etc/bashrc 2>/dev/null | head -1)
[ -f "${OF_BASHRC:-}" ] || { echo "ERROR: no OpenFOAM etc/bashrc found (OF_SUITE_ENV, of-env.sh, autodetect all empty); run /of-setup"; echo "__OFRC=3__"; exit 3; }
source "$OF_BASHRC" 2>/dev/null || true

sub=${1:-env}
shift || true
rc=0

case "$sub" in
env)
    echo "WM_PROJECT_DIR=${WM_PROJECT_DIR:-MISSING}"
    echo "WM_PROJECT_VERSION=${WM_PROJECT_VERSION:-MISSING}"
    echo "WM_OPTIONS=${WM_OPTIONS:-MISSING}"
    echo "FOAM_APPBIN=${FOAM_APPBIN:-MISSING} ($(ls ${FOAM_APPBIN:-/nonexistent} 2>/dev/null | wc -l) apps)"
    echo "FOAM_RUN=${FOAM_RUN:-MISSING}"
    echo "cores=$(nproc)"
    echo "mpirun=$(which mpirun 2>/dev/null || echo MISSING)"
    echo "gnuplot=$(which gnuplot 2>/dev/null || echo MISSING)"
    echo "pvpython=$(which pvpython 2>/dev/null || echo MISSING)"
    mkdir -p "${FOAM_RUN:?}"
    ;;

run)
    cs=$1; shift
    cd "$cs" 2>/dev/null || { echo "ERROR: case dir not found: $cs"; echo "__OFRC=2__"; exit 2; }
    app_base=$(basename "$1")
    log="log.$app_base"
    # divert -postProcess runs to their own log; never truncate the solver log
    case " $* " in *" -postProcess "*|*" -postProcess") log="log.${app_base}.postProcess";; esac
    "$@" >"$log" 2>&1
    rc=$?
    echo "--- tail -n 30 $PWD/$log ---"
    tail -n 30 "$log"
    ;;

par)
    cs=$1; n=$2; shift 2
    cd "$cs" 2>/dev/null || { echo "ERROR: case dir not found: $cs"; echo "__OFRC=2__"; exit 2; }
    if [ -n "${OF_NPROC_CAP:-}" ] && [ "$n" -gt "$OF_NPROC_CAP" ] 2>/dev/null; then
        echo "NOTE: ranks capped $n -> $OF_NPROC_CAP (OF_NPROC_CAP)"; n=$OF_NPROC_CAP
    fi
    app="$1"; shift
    app_base=$(basename "$app")
    log="log.$app_base"
    case " $* " in *" -postProcess "*|*" -postProcess") log="log.${app_base}.postProcess";; esac
    mpirun --oversubscribe -np "$n" "$app" -parallel "$@" >"$log" 2>&1
    rc=$?
    echo "--- tail -n 30 $PWD/$log ---"
    tail -n 30 "$log"
    ;;

sh)
    cs=$1; shift
    if [ "$cs" != "-" ]; then
        cd "$cs" 2>/dev/null || { echo "ERROR: case dir not found: $cs"; echo "__OFRC=2__"; exit 2; }
    fi
    eval "$@"
    rc=$?
    ;;

*)
    echo "ERROR: unknown subcommand '$sub' (env|run|par|sh)"
    rc=64
    ;;
esac

echo "__OFRC=${rc}__"
exit $rc
