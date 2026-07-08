#!/bin/bash
# Validation: lid-driven cavity Re=100 vs Ghia et al. (1982).
# Self-bootstrapping: if $FOAM_RUN/val-cavity-ghia is absent it is created
# from the icoFoam cavity tutorial with a 96x96 blockMeshDict and a
# centerline sample dict. Then configures, runs, samples, and compares.

# --- resolve OpenFOAM env: OF_SUITE_ENV -> of-env.sh (see of-env.example.sh) -> autodetect ---
_sd=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for _e in "${OF_SUITE_ENV:-}" "$_sd/of-env.sh" "$HOME/.config/openfoam-claude-suite/of-env.sh"; do
    [ -n "$_e" ] && [ -f "$_e" ] && { . "$_e"; break; }
done
[ -n "${OF_BASHRC:-}" ] || OF_BASHRC=$(ls -t /opt/OpenFOAM-*/etc/bashrc /usr/lib/openfoam/openfoam*/etc/bashrc 2>/dev/null | head -1)
[ -f "${OF_BASHRC:-}" ] || { echo "ERROR: no OpenFOAM etc/bashrc found (OF_SUITE_ENV, of-env.sh, autodetect all empty); run /of-setup"; echo "__OFRC=3__"; exit 3; }
source "$OF_BASHRC" 2>/dev/null || true

CASE=$FOAM_RUN/val-cavity-ghia
SCRIPTS=$_sd

if [ ! -d "$CASE" ]; then
    echo "BOOTSTRAP: creating $CASE from the cavity tutorial"
    mkdir -p "$FOAM_RUN"
    cp -r "$FOAM_TUTORIALS/incompressible/icoFoam/cavity/cavity" "$CASE" \
        || { echo "ERROR: cavity tutorial not found under $FOAM_TUTORIALS"; echo "__OFRC=2__"; exit 2; }
    cat > "$CASE/system/blockMeshDict" <<'BMD'
FoamFile { version 2.0; format ascii; class dictionary; object blockMeshDict; }
scale 0.1;
vertices ( (0 0 0) (1 0 0) (1 1 0) (0 1 0) (0 0 0.1) (1 0 0.1) (1 1 0.1) (0 1 0.1) );
blocks ( hex (0 1 2 3 4 5 6 7) (96 96 1) simpleGrading (1 1 1) );
edges ();
boundary (
    movingWall   { type wall;  faces ((3 7 6 2)); }
    fixedWalls   { type wall;  faces ((0 4 7 3) (2 6 5 1) (1 5 4 0)); }
    frontAndBack { type empty; faces ((0 3 2 1) (4 5 6 7)); }
);
mergePatchPairs ();
BMD
    cat > "$CASE/system/sample" <<'SMP'
type sets;
libs (sampling);
interpolationScheme cellPoint;
setFormat raw;
fields (U);
sets ( centerlineY { type uniform; axis distance; start (0.05 0 0.005); end (0.05 0.1 0.005); nPoints 200; } );
SMP
fi

cd "$CASE" || { echo "ERROR: case dir not found: $CASE"; echo "__OFRC=2__"; exit 2; }

# Re = U*L/nu = 1*0.1/0.001 = 100
foamDictionary -entry nu -set "0.001" constant/transportProperties > /dev/null
# transient control: dt for Co~0.77 on 96x96, run to t=12 s, write every 2 s
foamDictionary -entry endTime -set 12 system/controlDict > /dev/null
foamDictionary -entry deltaT -set 0.0008 system/controlDict > /dev/null
foamDictionary -entry writeControl -set runTime system/controlDict > /dev/null
foamDictionary -entry writeInterval -set 2 system/controlDict > /dev/null
foamDictionary -entry purgeWrite -set 0 system/controlDict > /dev/null
echo "CONFIG_DONE"

stage() { local n=$1; shift; echo "[$(date +%H:%M:%S)] START $n";
          "$@" > "log.$n" 2>&1 || { echo "STAGE_FAIL_$n"; tail -15 "log.$n"; exit 1; };
          echo "[$(date +%H:%M:%S)] OK $n"; }

stage blockMesh blockMesh
stage checkMesh checkMesh
grep -E "^ *cells:|Mesh OK" log.checkMesh
stage icoFoam icoFoam
tail -6 log.icoFoam | head -4
stage sample10 postProcess -func sample -time 10
stage sample12 postProcess -func sample -time 12

P12=postProcessing/sample/12/centerlineY_U.xy
P10=postProcessing/sample/10/centerlineY_U.xy
[ -f "$P12" ] || P12=$(ls postProcessing/sample/12*/centerlineY_U.xy 2>/dev/null | head -1)
[ -f "$P10" ] || P10=$(ls postProcessing/sample/10*/centerlineY_U.xy 2>/dev/null | head -1)
echo "profiles: $P10 $P12"

python3 "$SCRIPTS/ghia_compare.py" "$P12" "$P10" | tee ghia_result.txt

# overlay plot
cat > ghia-re100.dat <<'DAT'
0.0000 0.00000
0.0547 -0.03717
0.0625 -0.04192
0.0703 -0.04775
0.1016 -0.06434
0.1719 -0.10150
0.2813 -0.15662
0.4531 -0.21090
0.5000 -0.20581
0.6172 -0.13641
0.7344 0.00332
0.8516 0.23151
0.9531 0.68717
0.9609 0.73722
0.9688 0.78871
0.9766 0.84123
1.0000 1.00000
DAT
gnuplot <<GP
set terminal pngcairo size 800,600
set output "$CASE/ghia-comparison.png"
set xlabel "Ux / Ulid"
set ylabel "y / L"
set title "Lid-driven cavity Re=100: icoFoam 96x96 vs Ghia et al. (1982)"
set grid
set key left top
plot "$P12" using 2:(\$1/0.1) with lines lw 2 title "icoFoam (this run)", \
     "ghia-re100.dat" using 2:1 with points pt 7 ps 1.5 title "Ghia et al."
GP
echo "PLOT=$CASE/ghia-comparison.png"
echo "ALL_STAGES_DONE"
