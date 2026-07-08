#!/bin/bash
# ofmon.sh - OpenFOAM log monitor / convergence analyzer for Claude Code.
#
# Runs inside Linux. <scripts> = this directory as seen from Linux.
# Mode A (Windows host + WSL; <scripts> like /mnt/c/Users/<you>/...):
#   MSYS_NO_PATHCONV=1 wsl.exe -d <distro> --exec bash <scripts>/ofmon.sh <subcommand> ...
# Mode B (native Linux):
#   bash <scripts>/ofmon.sh <subcommand> ...
#
# Subcommands:
#   residuals <case> [logfile]   extract initial residuals per outer iteration
#                                -> <case>/residuals.csv, print last rows + verdict
#   errors <case> [logfile]      print FOAM FATAL / error blocks with context
#   plot <case> [logfile]        gnuplot residuals -> <case>/residuals.png
#   status <case> [logfile]      quick: last time, Courant, continuity, verdict
#
# Default logfile: newest solver log.* ("Solving for"); errors: newest log.*.
# Verdicts: CONVERGED | COMPLETED_ENDTIME | RUNNING_OK | DIVERGED | FATAL | NO_LOG
# Last line of output is always: __OFRC=<exit-code>__

# --- resolve OpenFOAM env: OF_SUITE_ENV -> of-env.sh (see of-env.example.sh) -> autodetect ---
_sd=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for _e in "${OF_SUITE_ENV:-}" "$_sd/of-env.sh" "$HOME/.config/openfoam-claude-suite/of-env.sh"; do
    [ -n "$_e" ] && [ -f "$_e" ] && { . "$_e"; break; }
done
[ -n "${OF_BASHRC:-}" ] || OF_BASHRC=$(ls -t /opt/OpenFOAM-*/etc/bashrc /usr/lib/openfoam/openfoam*/etc/bashrc 2>/dev/null | head -1)
[ -f "${OF_BASHRC:-}" ] || { echo "ERROR: no OpenFOAM etc/bashrc found (OF_SUITE_ENV, of-env.sh, autodetect all empty); run /of-setup"; echo "__OFRC=3__"; exit 3; }
source "$OF_BASHRC" 2>/dev/null || true

sub=${1:-status}
shift || true
rc=0

pick_log() {
    # $1 = case dir, $2 = optional explicit log, $3 = "any" -> newest overall
    # Default: newest log.* containing "Solving for", so utility logs
    # (reconstructPar, foamToVTK, ...) never shadow the solver verdict.
    if [ -n "${2:-}" ]; then echo "$2"; return; fi
    local l
    if [ "${3:-}" != "any" ]; then
        for l in $(ls -t "$1"/log.* 2>/dev/null); do
            grep -q "Solving for" "$l" 2>/dev/null && { echo "$l"; return; }
        done
    fi
    ls -t "$1"/log.* 2>/dev/null | head -1
}

extract_residuals() {
    # stdin: solver log -> stdout CSV: time,field,initialResidual
    awk '
    /^Time = /      { t=$3; sub(/s$/,"",t) }
    /Solving for /  {
        f=""; r=""
        for (i=1;i<=NF;i++) {
            if ($i=="for")     { f=$(i+1); sub(/,$/,"",f) }
            if ($i=="Initial") { r=$(i+3); sub(/,$/,"",r) }
        }
        if (f!="" && r!="" && !(t SUBSEP f in seen)) {
            seen[t,f]=1
            print t "," f "," r
        }
    }'
}

verdict_of() {
    # $1 = logfile
    local log=$1
    # crash signature set: FATAL errors AND signal-handler stack traces.
    # NOTE: never match generic "Floating point" - the harmless startup banner
    # "trapFpe: Floating point exception trapping enabled" would false-positive.
    if grep -qE "FOAM FATAL|sigFpe::sigHandler|error::printStack|MPI_ABORT|exited on signal" "$log"; then echo "FATAL"; return; fi
    if grep -qiE "solution converged in .* iterations" "$log"; then echo "CONVERGED"; return; fi
    if grep -qE "Initial residual = (nan|inf)" "$log"; then echo "DIVERGED"; return; fi
    # residual explosion check: any initial residual > 100 in last records
    local bad
    bad=$(extract_residuals < "$log" | tail -50 | awk -F, '$3+0 > 100 {c++} END{print c+0}')
    if [ "${bad:-0}" -gt 0 ]; then echo "DIVERGED"; return; fi
    if grep -q "^End$" "$log" || grep -q "Finalising parallel run" "$log"; then
        echo "COMPLETED_ENDTIME"; return
    fi
    echo "RUNNING_OK"
}

case "$sub" in
residuals)
    cs=$1; log=$(pick_log "$cs" "${2:-}")
    [ -n "$log" ] && [ -f "$log" ] || { echo "NO_LOG"; echo "__OFRC=1__"; exit 1; }
    extract_residuals < "$log" > "$cs/residuals.csv"
    n=$(wc -l < "$cs/residuals.csv")
    echo "log=$log rows=$n csv=$cs/residuals.csv"
    echo "--- first iteration ---"
    head -8 "$cs/residuals.csv"
    echo "--- last iteration(s) ---"
    tail -12 "$cs/residuals.csv"
    echo "verdict=$(verdict_of "$log")"
    ;;

errors)
    cs=$1; log=$(pick_log "$cs" "${2:-}" any)
    [ -n "$log" ] && [ -f "$log" ] || { echo "NO_LOG"; echo "__OFRC=1__"; exit 1; }
    echo "log=$log"
    if grep -q "FOAM FATAL" "$log"; then
        sed -n '/FOAM FATAL/,/^$/p' "$log" | head -40
    elif grep -qE "sigFpe::sigHandler|error::printStack" "$log"; then
        echo "crash: signal-handler stack trace (sigFpe/segv)"
        grep -E "^#[0-9]" "$log" | head -12
    else
        grep -niE "error|warning" "$log" | tail -20 || echo "no errors or warnings"
    fi
    ;;

plot)
    cs=$1; log=$(pick_log "$cs" "${2:-}")
    [ -n "$log" ] && [ -f "$log" ] || { echo "NO_LOG"; echo "__OFRC=1__"; exit 1; }
    extract_residuals < "$log" > "$cs/residuals.csv"
    fields=$(awk -F, '{print $2}' "$cs/residuals.csv" | sort -u)
    {
        echo "set terminal pngcairo size 900,600"
        echo "set output '$cs/residuals.png'"
        echo "set logscale y"
        echo "set xlabel 'Time / Iteration'"
        echo "set ylabel 'Initial residual'"
        echo "set grid"
        echo "set datafile separator ','"
        plotcmd="plot"
        for f in $fields; do
            plotcmd="$plotcmd '< grep \",$f,\" $cs/residuals.csv' using 1:3 with lines title '$f',"
        done
        echo "${plotcmd%,}"
    } | gnuplot 2>&1
    rc=$?
    [ -f "$cs/residuals.png" ] && echo "PLOT=$cs/residuals.png"
    ;;

status)
    cs=$1; log=$(pick_log "$cs" "${2:-}")
    [ -n "$log" ] && [ -f "$log" ] || { echo "NO_LOG"; echo "__OFRC=1__"; exit 1; }
    echo "log=$log"
    echo "lastTime=$(grep "^Time = " "$log" | tail -1)"
    echo "courant=$(grep "Courant Number" "$log" | tail -1)"
    echo "continuity=$(grep "continuity errors" "$log" | tail -1)"
    echo "execTime=$(grep "ExecutionTime" "$log" | tail -1)"
    echo "verdict=$(verdict_of "$log")"
    ;;

*)
    echo "ERROR: unknown subcommand '$sub' (residuals|errors|plot|status)"
    rc=64
    ;;
esac

echo "__OFRC=${rc}__"
exit $rc
