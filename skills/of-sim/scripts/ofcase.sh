#!/bin/bash
# ofcase.sh - OpenFOAM case lifecycle helpers for Claude Code automation.
#
# Runs inside Linux. <scripts> = this directory as seen from Linux.
# Mode A (Windows host + WSL; <scripts> like /mnt/c/Users/<you>/...):
#   MSYS_NO_PATHCONV=1 wsl.exe -d <distro> --exec bash <scripts>/ofcase.sh <subcommand> ...
# Mode B (native Linux):
#   bash <scripts>/ofcase.sh <subcommand> ...
#
# Subcommands:
#   new <template> <name>      copy tutorial template (path relative to
#                              $FOAM_TUTORIALS, or absolute) to $FOAM_RUN/<name>;
#                              restores 0/ from 0.orig; prints CASE=<path>
#   set <case> <file> <entry> <value>   foamDictionary -set (safe dict edit)
#   get <case> <file> <entry>           foamDictionary -value
#   info <case>                application, times, mesh presence, patches
#   clean <case>               remove results (times >0, processor*, logs,
#                              postProcessing); restore 0/ from 0.orig if present
#
# Last line of output is always: __OFRC=<exit-code>__

# --- resolve OpenFOAM env: OF_SUITE_ENV -> of-env.sh (see of-env.example.sh) -> autodetect ---
_sd=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for _e in "${OF_SUITE_ENV:-}" "$_sd/of-env.sh" "$HOME/.config/openfoam-claude-suite/of-env.sh"; do
    [ -n "$_e" ] && [ -f "$_e" ] && { . "$_e"; break; }
done
[ -n "${OF_BASHRC:-}" ] || OF_BASHRC=$(ls -t /opt/OpenFOAM-*/etc/bashrc /usr/lib/openfoam/openfoam*/etc/bashrc 2>/dev/null | head -1)
[ -f "${OF_BASHRC:-}" ] || { echo "ERROR: no OpenFOAM etc/bashrc found (OF_SUITE_ENV, of-env.sh, autodetect all empty); run /of-setup"; echo "__OFRC=3__"; exit 3; }
source "$OF_BASHRC" 2>/dev/null || true

sub=${1:-help}
shift || true
rc=0

case "$sub" in
new)
    tpl=$1; name=$2
    src="$tpl"
    [ -d "$src" ] || src="$FOAM_TUTORIALS/$tpl"
    if [ ! -d "$src" ]; then
        echo "ERROR: template not found: $tpl"; echo "__OFRC=2__"; exit 2
    fi
    mkdir -p "$FOAM_RUN"
    dst="$FOAM_RUN/$name"
    if [ -e "$dst" ]; then
        echo "ERROR: target already exists: $dst"; echo "__OFRC=3__"; exit 3
    fi
    cp -r "$src" "$dst"
    rm -f "$dst"/log.* 2>/dev/null
    rm -rf "$dst"/postProcessing "$dst"/processor* 2>/dev/null
    if [ -d "$dst/0.orig" ] && [ ! -d "$dst/0" ]; then
        cp -r "$dst/0.orig" "$dst/0"
    fi
    echo "TEMPLATE=$src"
    echo "CASE=$dst"
    ls "$dst"
    ;;

set)
    cs=$1; file=$2; entry=$3; value=$4
    cd "$cs" || { echo "ERROR: no case: $cs"; echo "__OFRC=2__"; exit 2; }
    foamDictionary -entry "$entry" -set "$value" "$file"
    rc=$?
    [ $rc -eq 0 ] && echo "SET $file :: $entry = $value"
    ;;

get)
    cs=$1; file=$2; entry=$3
    cd "$cs" || { echo "ERROR: no case: $cs"; echo "__OFRC=2__"; exit 2; }
    foamDictionary -entry "$entry" -value "$file"
    rc=$?
    ;;

info)
    cs=$1
    cd "$cs" || { echo "ERROR: no case: $cs"; echo "__OFRC=2__"; exit 2; }
    echo "case=$PWD"
    echo "application=$(foamDictionary -entry application -value system/controlDict 2>/dev/null || echo unknown)"
    echo "times=$(foamListTimes -withZero 2>/dev/null | tr '\n' ' ')"
    if [ -d constant/polyMesh ] && [ -e constant/polyMesh/owner ]; then
        echo "mesh=present"
        echo "patches: $(grep -E '^\s+\w+$' constant/polyMesh/boundary 2>/dev/null | tr -d ' \t' | tr '\n' ' ')"
    else
        echo "mesh=none"
    fi
    ls log.* 2>/dev/null | tr '\n' ' '; echo ""
    ;;

clean)
    cs=$1
    cd "$cs" || { echo "ERROR: no case: $cs"; echo "__OFRC=2__"; exit 2; }
    foamListTimes -rm 2>/dev/null
    rm -rf processor* postProcessing log.* residuals.csv residuals.png 2>/dev/null
    if [ -d 0.orig ]; then rm -rf 0; cp -r 0.orig 0; echo "0/ restored from 0.orig"; fi
    echo "cleaned $PWD"
    ;;

*)
    echo "ERROR: unknown subcommand '$sub' (new|set|get|info|clean)"
    rc=64
    ;;
esac

echo "__OFRC=${rc}__"
exit $rc
