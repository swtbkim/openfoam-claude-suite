#!/bin/bash
# Validation pipeline: motorBike external aero (snappyHexMesh + parallel simpleFoam).
# Mirrors the tutorial Allrun, executed stage by stage with explicit markers.
# Ranks: nproc, lowered to OF_NPROC_CAP if set.

# --- resolve OpenFOAM env: OF_SUITE_ENV -> of-env.sh (see of-env.example.sh) -> autodetect ---
_sd=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for _e in "${OF_SUITE_ENV:-}" "$_sd/of-env.sh" "$HOME/.config/openfoam-claude-suite/of-env.sh"; do
    [ -n "$_e" ] && [ -f "$_e" ] && { . "$_e"; break; }
done
[ -n "${OF_BASHRC:-}" ] || OF_BASHRC=$(ls -t /opt/OpenFOAM-*/etc/bashrc /usr/lib/openfoam/openfoam*/etc/bashrc 2>/dev/null | head -1)
[ -f "${OF_BASHRC:-}" ] || { echo "ERROR: no OpenFOAM etc/bashrc found (OF_SUITE_ENV, of-env.sh, autodetect all empty); run /of-setup"; echo "__OFRC=3__"; exit 3; }
source "$OF_BASHRC" 2>/dev/null || true

N=$(nproc)
if [ -n "${OF_NPROC_CAP:-}" ] && [ "$N" -gt "$OF_NPROC_CAP" ] 2>/dev/null; then N=$OF_NPROC_CAP; fi
echo "RANKS=$N"

CASE=$FOAM_RUN/val-motorbike
rm -rf "$CASE"
cp -r "$FOAM_TUTORIALS/incompressible/simpleFoam/motorBike" "$CASE"
cd "$CASE" || exit 1
echo "CASE=$CASE"

mkdir -p constant/triSurface
cp -f "$FOAM_TUTORIALS"/resources/geometry/motorBike.obj.gz constant/triSurface/
cp system/decomposeParDict.6 system/decomposeParDict
foamDictionary -entry numberOfSubdomains -set "$N" system/decomposeParDict > /dev/null
foamDictionary -entry method -set scotch system/decomposeParDict > /dev/null

run_stage() {
    local name=$1; shift
    echo "[$(date +%H:%M:%S)] START $name"
    "$@" > "log.$name" 2>&1
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "STAGE_FAIL_$name rc=$rc"
        tail -20 "log.$name"
        exit 1
    fi
    echo "[$(date +%H:%M:%S)] OK $name"
}

run_stage surfaceFeatureExtract surfaceFeatureExtract
run_stage blockMesh blockMesh
run_stage decomposePar decomposePar
run_stage snappyHexMesh mpirun --oversubscribe -np "$N" snappyHexMesh -overwrite -parallel
run_stage topoSet mpirun --oversubscribe -np "$N" topoSet -parallel
for d in processor*; do rm -rf "$d/0"; cp -r 0.orig "$d/0"; done
echo "restore0Dir done"
run_stage potentialFoam mpirun --oversubscribe -np "$N" potentialFoam -writephi -parallel
checkMesh_log() { mpirun --oversubscribe -np "$N" checkMesh -parallel; }
run_stage checkMesh checkMesh_log
grep -E "^ *cells:|Mesh OK|Failed" log.checkMesh | head -5
run_stage simpleFoam mpirun --oversubscribe -np "$N" simpleFoam -parallel
run_stage reconstructParMesh reconstructParMesh -constant
run_stage reconstructPar reconstructPar -latestTime
echo "ALL_STAGES_DONE"
