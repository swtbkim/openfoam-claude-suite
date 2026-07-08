# Numerics presets: fvSchemes, fvSolution, controlDict (v2412)

Pick ONE preset per case (robust -> standard -> accurate). Start standard; drop to robust
on divergence; move to accurate only after converged baseline exists.

## fvSchemes presets

### STANDARD (steady RAS, production default)
```
ddtSchemes      { default steadyState; }
gradSchemes     { default Gauss linear; limited cellLimited Gauss linear 1; grad(U) $limited; grad(k) $limited; grad(omega) $limited; }
divSchemes      { default none;
                  div(phi,U) bounded Gauss linearUpwind limited;
                  div(phi,k) bounded Gauss limitedLinear 1;
                  div(phi,omega) bounded Gauss limitedLinear 1;
                  div(phi,epsilon) bounded Gauss limitedLinear 1;
                  div((nuEff*dev2(T(grad(U))))) Gauss linear; }
laplacianSchemes{ default Gauss linear corrected; }   // limited corrected 0.33 if nonOrtho>70
interpolationSchemes { default linear; }
snGradSchemes   { default corrected; }
wallDist        { method meshWave; }
```

### ROBUST (first aid; guaranteed bounded)
ddt `Euler` (transient) or `steadyState`; ALL div(phi,X) -> `bounded Gauss upwind`
(transient: `Gauss upwind`, no bounded); gradSchemes default `cellLimited Gauss linear 1`;
laplacian `Gauss linear limited corrected 0.33`.

### ACCURATE (transient LES/DES or final steady)
ddt `backward` (or CrankNicolson 0.9); div(phi,U) `Gauss linear` (LES) /
`Gauss linearUpwind grad(U)` (RAS transient); turbulence divs limitedLinear 1.

VOF (interFoam) extras: `div(phirb,alpha) Gauss interfaceCompression;`
`div(phi,alpha) Gauss vanLeer;` ddt `Euler`.

## fvSolution presets

### Steady SIMPLE (simpleFoam family)
```
solvers {
  p     { solver GAMG; smoother GaussSeidel; tolerance 1e-7; relTol 0.05; }
  "(U|k|omega|epsilon)" { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-8; relTol 0.1; }
}
SIMPLE {
  consistent yes;                       // SIMPLEC -> higher relaxation OK
  nNonOrthogonalCorrectors 0;           // 1-2 if mesh nonOrtho > 60
  residualControl { p 1e-4; U 1e-5; "(k|omega|epsilon)" 1e-5; }
}
relaxationFactors {
  fields    { p 0.3; }                  // only needed when consistent no
  equations { U 0.9; ".*" 0.9; }        // consistent yes: 0.9; classic: U 0.7
}
```
Robust fallback: `consistent no; fields { p 0.3; } equations { U 0.7; "(k|omega|epsilon)" 0.7; }`.

### Transient PIMPLE (pimpleFoam family)
```
solvers {
  p      { solver GAMG; smoother GaussSeidel; tolerance 1e-7; relTol 0.05; }
  pFinal { $p; relTol 0; }
  "(U|k|omega|epsilon)"      { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-8; relTol 0.1; }
  "(U|k|omega|epsilon)Final" { $U; relTol 0; }
}
PIMPLE {
  nOuterCorrectors 1;     // 1 = PISO mode (Co<1); 2-3 + relaxation for large Co
  nCorrectors 2;
  nNonOrthogonalCorrectors 0;
}
```
icoFoam/pisoFoam use `PISO { nCorrectors 2; nNonOrthogonalCorrectors 0; }`; closed
domains add `pRefCell 0; pRefValue 0;`.
interFoam adds: `"alpha.water.*" { nAlphaCorr 2; nAlphaSubCycles 1; cAlpha 1; MULESCorr yes; nLimiterIter 3; solver smoothSolver; smoother symGaussSeidel; tolerance 1e-8; relTol 0; }`
and momentumPredictor no (low Re).

## controlDict patterns

### Steady
```
application simpleFoam;  startFrom latestTime;  startTime 0;
stopAt endTime;  endTime 3000;  deltaT 1;
writeControl timeStep;  writeInterval 500;  purgeWrite 3;
runTimeModifiable true;
```
(residualControl usually stops it earlier -> verdict CONVERGED.)

### Transient (fixed dt)
`deltaT = Co_target * dx_min / U_max` with Co_target 0.5 (explicit-ish interFoam) to 2-5
(PIMPLE outer-corrected). endTime = N flow-throughs (N>=3 to wash transients) or the
user-requested physical time. `writeControl runTime; writeInterval <endTime/50>; purgeWrite 0;`

### Transient (adaptive dt - interFoam etc.)
```
adjustTimeStep yes;  maxCo 1;  maxAlphaCo 1;  maxDeltaT 1;
writeControl adjustableRunTime;
```
pimpleFoam supports adjustTimeStep too (with nOuterCorrectors>1 can run maxCo 2-5).

### functions block (add to controlDict)
```
functions {
  #includeFunc solverInfo            // residuals to postProcessing/
  // forces on a body:
  forces1 { type forces; libs (forces); patches (body); rho rhoInf; rhoInf 1.2; CofR (0 0 0); writeControl timeStep; writeInterval 10; }
  // forceCoeffs: add liftDir/dragDir/pitchAxis, magUInf, lRef, Aref
  // ready-made: #includeEtc "caseDicts/postProcessing/forces/forceCoeffs.cfg" etc.
}
```

## Increasing the time step (run a transient faster on adaptive dt)

With `adjustTimeStep yes`, dt = min over all ACTIVE limiters of (limit / current),
then capped by `maxDeltaT`:
- bulk flow:      `maxCo / CoNum`          (every solver)
- VOF interface:  `maxAlphaCo / alphaCoNum`  (interFoam/multiphaseInter*/VOF+CHT)
- solid diffusion:`maxDi / DiNum`           (chtMultiRegion* only)
- hard cap:       `maxDeltaT`

**Step 1 - find the BINDING limiter (never raise knobs blindly).** Read the per-step log
(`ofmon.sh status`, or grep the solver log):
- `Courant Number ... max: X`           -> X near maxCo      => bulk flow binds
- `Interface Courant Number ... max: Y`  -> Y near maxAlphaCo  => interface binds (VOF)
- dt pinned at maxDeltaT while both Courants sit well below max => the cap binds

**Step 2 - raise only the binding one:**
| binds | raise | guard / safe ceiling |
|---|---|---|
| maxDeltaT (cap) | maxDeltaT | free win; raise until a Courant limiter takes over |
| maxCo (bulk) | maxCo | explicit/1-corrector: keep <1. PIMPLE nOuterCorrectors>=2 (+relax): 2-5 |
| maxAlphaCo (VOF) | maxAlphaCo and/or nAlphaSubCycles | gate on alpha bounds (below) |
| maxDi (CHT solid) | maxDi | rarely binds; solid conduction is cheap |

**VOF interface-Courant rules (validated on pinFinJetCooling VOF+CHT):**
- For free-surface (+ CHT) cases the INTERFACE Courant binds, not maxCo (measured
  alphaCo 0.499 vs bulk Co 0.417). Tune `maxAlphaCo`, not `maxCo`.
- `maxAlphaCo` and `nAlphaSubCycles` trade off: each MULES sub-cycle advects at
  Co = maxAlphaCo / nAlphaSubCycles. Either raise maxAlphaCo with more sub-cycles
  (bounded, more alpha work) or cut sub-cycles at the same maxAlphaCo (cheaper).
  `nAlphaSubCycles 2->1` at maxAlphaCo 0.5 was stable and ~10% faster.
- ACCEPTANCE GATE: watch `Min/Max(alpha.water)` in the log. ~1e-10 excursions are
  machine noise; a clear overshoot (e.g. Max=1.0000003 at maxAlphaCo 1.0 +
  nAlphaSubCycles 1) means the interface is under-resolved -> back off. High
  maxAlphaCo also smears the interface (OK only if the surface is not the QoI).
- CrankNicolson ddt is incompatible with nAlphaSubCycles>1 (interFoam FatalErrors);
  keep `Euler`.
- PREREQUISITE for custom/ported multi-region VOF solvers: the solver must feed
  alphaCoNum INTO the dt controller. If "Interface Courant Number" prints but
  raising maxAlphaCo does not change dt, the limiter is not wired in (a real bug
  seen in a ported chtMultiRegionInterFoam: maxAlphaCo was computed but ignored,
  so dt was set by maxCo alone). Stock interFoam/interIsoFoam wire it correctly.

**Orthogonal lever - cut per-step cost (does NOT change dt; stacks with the above).**
Validated VOF+CHT settings tuning, -28% wall-clock, accuracy-neutral, each gated on
QoI + alpha bounds:
- `p`/`p_rgh`: loosen intermediate `relTol 0.01->0.05`, keep `*Final relTol 0` (the
  tight final solve preserves mass conservation). -4%.
- PIMPLE `nCorrectors 2->1`: halves the dominant pressure solves, -19%. CAVEAT (VOF):
  the 2nd corrector also stabilises the explicit surface-tension term; restore 2 if
  parasitic interface currents / alpha overshoot appear.
- energy advection `div(rhoPhi,T)` (or `div(phi,T)`) upwind->`limitedLinear 1`:
  2nd-order, small cost, better thermal QoI. Do NOT apply to `div(rhoPhi,U)` when
  `momentumPredictor no` - it feeds UEqn.H()/A() -> HbyA -> the pressure system and
  ran +12% slower.
- multi-region CHT: `energyCoupling { convergence { "T" 1e-3; } }` skips the energy
  sub-loop in quasi-steady; an adaptive outer-corrector reduction can ~halve pressure
  work once flow+thermal settle (needs a consecutive-steps hysteresis or an isolated
  transient dip under-resolves and diverges).
- Looked helpful, was net-negative (always benchmark on WALL-CLOCK, not iteration
  count): GAMG smoother `DIC->DICGaussSeidel` (-5.5% cycles but +5% wall-clock at
  ~83k serial); `maxAlphaCo 1.0` (alpha overshoot).

## Linear solver notes
- p: GAMG almost always; PCG+DIC for tiny meshes (cavity) or as GAMG fallback.
- Tolerances: tighter `pFinal` (relTol 0) matters for transient mass conservation.
- potentialFoam needs `Phi` solver entry (clone of p) + `POTENTIAL` block when used
  as initializer: `potentialFoam -writephi`; template if absent:
  `Phi { solver GAMG; smoother GaussSeidel; tolerance 1e-06; relTol 0.01; }`

## Rotating-machinery stabilization preset (validated: 2D/3D mixer, AMI + kEpsilon)

Impulsive start (rotor at full speed from t=0) diverges around the FIRST revolution:
local Co spikes (3 -> 450+), deltaT collapses to ~1e-5, SIGFPE inside
kEpsilon::correct(). Always ramp the rotation in constant/dynamicMeshDict:
```
omega   table ((0 0) (<t_ramp> <omega>) (1e6 <omega>));   // t_ramp ~ 1 s or ~half rev
```
- PIMPLE with nOuterCorrectors 3 + relaxation (U/k/eps 0.7, *Final 1.0; p 0.3,
  pFinal 1) runs stably at maxCo 2 (up to ~4 with care). The default maxCo 0.5
  pins dt to the finest tip cells and makes 3D rotating cases ~4-10x more
  expensive than necessary.
- Also cap dt by rotation angle for AMI quality:
  `maxDeltaT = (1..2 deg)*pi/180 / omega`.
- Keep `runTimeModifiable true`: maxCo/endTime can be retuned mid-run.
- Start-up phase: div(phi,U) upwind + cellLimited gradients; switch to
  linearUpwind after the flow is established if accuracy matters.

## Runtime function objects: passive tracer + mixing metrics (keywords verified in v2412 source)

Passive scalar solved alongside any solver (controlDict functions{}):
```
sTransport { type scalarTransport; libs (solverFunctionObjects);
             field s; bounded01 true; phi phi; nut nut; D 1e-09;
             schemesField s; writeControl writeTime; }
```
Requires: a 0/s field (zeroGradient walls, cyclicAMI on AMI patches),
`div(phi,s) Gauss limitedLinear01 1` in fvSchemes, and `"(k|epsilon|s)"`
(+ `...Final`) solver entries in fvSolution.

Volume statistics time series (postProcessing/<name>/0/volFieldValue.dat):
```
tracerCoV { type volFieldValue; libs (fieldFunctionObjects); regionType all;
            operation CoV; fields (s); writeControl runTime; writeInterval <dt>;
            log false; writeFields false; }
tracerAvg { ...same...; operation volAverage; }   // conservation gate: drift < 0.1%
```
TRAP: CoV = stddev/mean -> an all-zero field gives 0/0 (SIGFPE under trapFpe).
Seed the field (setFields) BEFORE the first function-object evaluation.

## Divergence remediation ladder (apply one step at a time)
1. Relaxation down: SIMPLE consistent no, p 0.3 / U 0.7 / turb 0.7.
2. div(phi,U) -> upwind (ROBUST preset), gradients cellLimited 1.
3. Transient: halve deltaT or set adjustTimeStep + maxCo 0.5.
4. Initialize: `potentialFoam -writephi` before the solver (add Phi entries).
5. ddt -> Euler (from backward/CN); turbulence: start kEpsilon then switch kOmegaSST.
6. Mesh: refine/repair worst cells (back to meshing.md quality table).
Bounding spam on k/omega/epsilon -> inflow values wrong (recompute) or mesh quality.
