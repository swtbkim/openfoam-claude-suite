#!/bin/bash
# Validation: NL scenario "steady turbulent air over backward-facing step, 15 m/s"
# = of-sim --auto pipeline on pitzDaily template with physics-consistent edits.

# --- resolve OpenFOAM env: OF_SUITE_ENV -> of-env.sh (see of-env.example.sh) -> autodetect ---
_sd=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for _e in "${OF_SUITE_ENV:-}" "$_sd/of-env.sh" "$HOME/.config/openfoam-claude-suite/of-env.sh"; do
    [ -n "$_e" ] && [ -f "$_e" ] && { . "$_e"; break; }
done
[ -n "${OF_BASHRC:-}" ] || OF_BASHRC=$(ls -t /opt/OpenFOAM-*/etc/bashrc /usr/lib/openfoam/openfoam*/etc/bashrc 2>/dev/null | head -1)
[ -f "${OF_BASHRC:-}" ] || { echo "ERROR: no OpenFOAM etc/bashrc found (OF_SUITE_ENV, of-env.sh, autodetect all empty); run /of-setup"; echo "__OFRC=3__"; exit 3; }
source "$OF_BASHRC" 2>/dev/null || true

S=$_sd
CASE=$FOAM_RUN/val-step15

if [ ! -d "$CASE" ]; then
    bash "$S/ofcase.sh" new incompressible/simpleFoam/pitzDaily val-step15 | grep CASE=
fi
cd "$CASE" || exit 1

# P3: inlet 15 m/s; I=5% -> k=1.5*(15*0.05)^2=0.84375; eps,omega scaled from template
foamDictionary -entry "boundaryField/inlet/value" -set "uniform (15 0 0)" 0/U > /dev/null
for e in internalField "boundaryField/inlet/value" "boundaryField/upperWall/value" "boundaryField/lowerWall/value"; do
    foamDictionary -entry "$e" -set "uniform 0.84375" 0/k > /dev/null
    foamDictionary -entry "$e" -set "uniform 50.136" 0/epsilon > /dev/null
done
foamDictionary -entry internalField -set "uniform 660.22" 0/omega > /dev/null
foamDictionary -entry "SIMPLE/residualControl/p" -set "1e-4" system/fvSolution > /dev/null
foamDictionary -entry "SIMPLE/residualControl/U" -set "1e-5" system/fvSolution > /dev/null
echo "EDITS_DONE U.inlet=$(foamDictionary -entry boundaryField/inlet/value -value 0/U | tr -d '\n')"
echo "k=$(foamDictionary -entry internalField -value 0/k) eps=$(foamDictionary -entry internalField -value 0/epsilon) RAS=$(foamDictionary -entry RAS/RASModel -value constant/turbulenceProperties)"

stage() { local n=$1; shift; echo "[$(date +%H:%M:%S)] START $n";
          "$@" > "log.$n" 2>&1 || { echo "STAGE_FAIL_$n"; tail -15 "log.$n"; exit 1; };
          echo "[$(date +%H:%M:%S)] OK $n"; }

stage blockMesh blockMesh
stage checkMesh checkMesh
grep -E "^ *cells:|Mesh OK" log.checkMesh
stage simpleFoam simpleFoam
grep -E "solution converged|^Time = " log.simpleFoam | tail -2

# P5/P6: yPlus, wall shear, reattachment, mass balance
stage yPlus simpleFoam -postProcess -func yPlus -latestTime
grep -A1 "patch lowerWall" log.yPlus | head -2 ; grep "y+" log.yPlus | head -3
stage wallShearStress simpleFoam -postProcess -func wallShearStress -latestTime

cat > system/wallSample <<'WS'
FoamFile { version 2.0; format ascii; class dictionary; object wallSample; }
type            surfaces;
libs            (sampling);
interpolationScheme cell;
surfaceFormat   raw;
fields          (wallShearStress);
surfaces ( lower { type patch; patches (lowerWall); } );
WS
stage wallSample postProcess -func wallSample -latestTime

RAW=$(ls postProcessing/wallSample/*/wallShearStress_lower.raw 2>/dev/null | tail -1)
echo "RAW=$RAW"
python3 - "$RAW" <<'PY'
import sys
rows = []
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) >= 6 and not line.startswith('#'):
        try:
            x, y, z, tx = float(p[0]), float(p[1]), float(p[2]), float(p[3])
        except ValueError:
            continue
        if y < -0.024:          # bottom wall downstream of the step
            rows.append((x, tx))
rows.sort()
# main reattachment = downstream edge of the LAST negative-tau_x stretch
# (the first crossing after the step is the secondary corner vortex)
xr = None
last_neg = None
for i, (x, t) in enumerate(rows):
    if t < 0.0:
        last_neg = i
if last_neg is not None and last_neg + 1 < len(rows):
    x0, t0 = rows[last_neg]
    x1, t1 = rows[last_neg + 1]
    xr = x0 + (x1 - x0) * (0.0 - t0) / (t1 - t0)
h = 0.0254
if xr:
    print(f"REATTACHMENT x={xr:.4f} m  x/h={xr/h:.2f} (step h={h} m)")
else:
    print("REATTACHMENT not found (no sign change)")
PY

stage flowIn  postProcess -func 'flowRatePatch(name=inlet)'  -latestTime
stage flowOut postProcess -func 'flowRatePatch(name=outlet)' -latestTime
ls postProcessing/ | tr '\n' ' '; echo ""
for d in postProcessing/flowRatePatch*; do
    for f in "$d"/*/surfaceFieldValue.dat; do
        [ -f "$f" ] && echo "$d: $(tail -1 "$f")"
    done
done

bash "$S/ofmon.sh" plot "$CASE" "$CASE/log.simpleFoam" | grep PLOT
bash "$S/ofmon.sh" status "$CASE" "$CASE/log.simpleFoam" | grep -E "verdict|lastTime"
echo "ALL_STAGES_DONE"
