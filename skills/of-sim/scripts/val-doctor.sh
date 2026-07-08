#!/bin/bash
# of-doctor validation: two deliberate faults on a cavity clone, with evidence
# capture, fix, and verified recovery.

# --- resolve OpenFOAM env: OF_SUITE_ENV -> of-env.sh (see of-env.example.sh) -> autodetect ---
_sd=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for _e in "${OF_SUITE_ENV:-}" "$_sd/of-env.sh" "$HOME/.config/openfoam-claude-suite/of-env.sh"; do
    [ -n "$_e" ] && [ -f "$_e" ] && { . "$_e"; break; }
done
[ -n "${OF_BASHRC:-}" ] || OF_BASHRC=$(ls -t /opt/OpenFOAM-*/etc/bashrc /usr/lib/openfoam/openfoam*/etc/bashrc 2>/dev/null | head -1)
[ -f "${OF_BASHRC:-}" ] || { echo "ERROR: no OpenFOAM etc/bashrc found (OF_SUITE_ENV, of-env.sh, autodetect all empty); run /of-setup"; echo "__OFRC=3__"; exit 3; }
source "$OF_BASHRC" 2>/dev/null || true

S=$_sd
C=$FOAM_RUN/val-broken
rm -rf "$C"
bash "$S/ofcase.sh" new incompressible/icoFoam/cavity/cavity val-broken | grep CASE=
cd "$C" || exit 1
blockMesh > log.blockMesh 2>&1

echo "===== FAULT 1: deltaT 0.05 (Courant ~8.5) ====="
foamDictionary -entry deltaT -set 0.05 system/controlDict > /dev/null
icoFoam > log.icoFoam 2>&1
echo "solver rc=$? (expected nonzero)"
echo "--- evidence: ofmon status ---"
bash "$S/ofmon.sh" status "$C" "$C/log.icoFoam" | grep -E "courant|verdict"
echo "--- evidence: last residuals ---"
bash "$S/ofmon.sh" residuals "$C" "$C/log.icoFoam" 2>/dev/null | tail -4 | head -3
echo "--- evidence: crash signature ---"
grep -m2 -E "sigFpe|Floating point|FOAM FATAL" log.icoFoam

echo "===== FIX 1: deltaT -> 0.005 (Co ~0.85), clean, rerun ====="
foamDictionary -entry deltaT -set 0.005 system/controlDict > /dev/null
foamListTimes -rm 2>/dev/null
icoFoam > log.icoFoam 2>&1
bash "$S/ofmon.sh" status "$C" "$C/log.icoFoam" | grep -E "courant|verdict"

echo "===== FAULT 2: remove div(phi,U) scheme ====="
foamDictionary -entry "divSchemes/div(phi,U)" -remove system/fvSchemes > /dev/null
foamListTimes -rm 2>/dev/null
icoFoam > log.icoFoam 2>&1
echo "solver rc=$? (expected nonzero)"
sed -n '/FOAM FATAL/,/^$/p' log.icoFoam | head -8

echo "===== FIX 2: restore scheme, rerun ====="
foamDictionary -entry "divSchemes/div(phi,U)" -set "Gauss linear" system/fvSchemes > /dev/null
icoFoam > log.icoFoam 2>&1
bash "$S/ofmon.sh" status "$C" "$C/log.icoFoam" | grep verdict
echo "DOCTOR_DEMO_DONE"
