# OpenFOAM case anatomy, fields, and boundary conditions (v2412)

## Directory layout

```
case/
  0/ (or 0.orig/)      initial+boundary fields: U, p, [k, omega, epsilon, nut, T, alpha.*]
  constant/
    polyMesh/          mesh: points, faces, owner, neighbour, boundary  (written by blockMesh/snappy)
    transportProperties / thermophysicalProperties / turbulenceProperties
    [g, radiationProperties, regionProperties, triSurface/]
  system/
    controlDict        time control, writeControl, functions{}
    fvSchemes          discretization schemes
    fvSolution         linear solvers, SIMPLE/PIMPLE/PISO controls, relaxation
    [blockMeshDict, snappyHexMeshDict, decomposeParDict, setFieldsDict, topoSetDict, sampleDict]
  <time dirs>/         results per write time (0.1/, 100/, ...)
  processor<N>/        decomposed mesh+fields when parallel
  postProcessing/      functionObject outputs (CSV/dat)
  log.<app>            per-application logs (convention)
```

Every OpenFOAM file = C++-style dictionary with `FoamFile` header:
```
FoamFile { version 2.0; format ascii; class <volScalarField|volVectorField|dictionary|polyBoundaryMesh>; object <name>; }
```
Macros: `$internalField`, `$p` (reference sibling entry), `#include "file"`,
`#includeEtc "caseDicts/..."` (resolves into $WM_PROJECT_DIR/etc/).

`dimensions [kg m s K mol A cd]`. Common:
| field | dimensions | note |
|---|---|---|
| U | [0 1 -1 0 0 0 0] | m/s |
| p (incompressible) | [0 2 -2 0 0 0 0] | KINEMATIC p/rho, m2/s2 |
| p, p_rgh (compressible/buoyant/VOF) | [1 -1 -2 0 0 0 0] | Pa |
| k | [0 2 -2 0 0 0 0] | nut [0 2 -1 0 0 0 0] |
| omega | [0 0 -1 0 0 0 0] | epsilon [0 2 -3 0 0 0 0] |
| T | [0 0 0 1 0 0 0] | alpha.water dimensionless |
| nu (transportProperties) | [0 2 -1 0 0 0 0] | v2412 accepts bare `nu 1e-05;` |

## BC tables by patch role (incompressible turbulent reference set)

| field | inlet | outlet | wall | far-field/open |
|---|---|---|---|---|
| U | fixedValue (u 0 0) | zeroGradient (or inletOutlet val (0 0 0)) | noSlip | freestreamVelocity / pressureInletOutletVelocity |
| p | zeroGradient | fixedValue 0 | zeroGradient | freestreamPressure / totalPressure p0 |
| k | fixedValue k_in | zeroGradient | kqRWallFunction $internalField | inletOutlet |
| omega | fixedValue w_in | zeroGradient | omegaWallFunction $internalField | inletOutlet |
| epsilon | fixedValue e_in | zeroGradient | epsilonWallFunction $internalField | inletOutlet |
| nut | calculated 0 | calculated 0 | nutkWallFunction 0 (nutUSpaldingWallFunction if y+<30 mixed) | calculated 0 |
| T | fixedValue T_in | zeroGradient/inletOutlet | zeroGradient (fixedValue for heated, externalWallHeatFluxTemperature for HTC) | inletOutlet |

Special patch types (must match constant/polyMesh/boundary `type`):
- 2D: `empty` on the two parallel planes (mesh exactly 1 cell thick).
- Axisymmetric: `wedge` front/back (< 5 deg sector, 1 cell).
- `symmetry` / `symmetryPlane`; `cyclic`/`cyclicAMI` (pairs); `mappedWall` (CHT interfaces).
- Backflow-safe outlet pair: U `inletOutlet inletValue (0 0 0)` + p `fixedValue`.
- Velocity-driven without pressure ref: closed domains need `pRefCell 0; pRefValue 0;`
  in SIMPLE/PIMPLE/PISO block of fvSolution.
- Flow-rate inlet: U `flowRateInletVelocity volumetricFlowRate <m3/s>`.
- VOF (interFoam): `alpha.water` inlet fixedValue 1/0, walls zeroGradient, atmosphere
  `inletOutlet inletValue 0`; p_rgh atmosphere `totalPressure p0 0`; U atmosphere
  `pressureInletOutletVelocity`.

Multi-region (CHT) anatomy:
- Per-region dirs: 0/<region>, constant/<region>, system/<region>;
  constant/regionProperties lists the fluid/solid regions.
- Interface BC pair `compressible::turbulentTemperatureRadCoupledMixed` on mappedWall patches.
- Per-region flag: `checkMesh/postProcess/foamDictionary ... -region <name>`.
- Parallel: per-region system/<region>/decomposeParDict, then `decomposePar -allRegions`.
- splitMeshRegions/changeDictionary sequencing: follow the cloned tutorial's Allrun.

## Turbulence inflow estimation (when user gives only U)

Turbulence intensity I: internal flow 5% (default), external/quiet 1%, very turbulent 10%.
Length scale L = 0.07 * Dh (internal, Dh = hydraulic diameter) or 0.07 * chord (external).
```
k       = 1.5 * (U * I)^2
epsilon = Cmu^0.75 * k^1.5 / L          (Cmu = 0.09)
omega   = sqrt(k) / (Cmu^0.25 * L)
nut(init) = 0  (calculated)
```
Sanity: pitzDaily uses U=10, I=5% -> k=0.375, omega=440 (L~2.5mm); same order expected.

## constant/ property files

Incompressible (`transportProperties`):
```
transportModel  Newtonian;
nu              1.5e-05;        // air 20C; water: 1.0e-06
```
Non-Newtonian models: CrossPowerLaw, BirdCarreau, HerschelBulkley, powerLaw (set
transportModel + coeff sub-dict).

`turbulenceProperties`:
```
simulationType  RAS;            // laminar | RAS | LES
RAS { RASModel kOmegaSST; turbulence on; printCoeffs on; }
```

Compressible/buoyant (`thermophysicalProperties`): hePsiThermo (gas) or heRhoThermo
(buoyant/liquid), pureMixture, perfectGas, hConst/janaf, sutherland/const transport.
Buoyant cases also need `constant/g`:
```
dimensions [0 1 -2 0 0 0 0]; value (0 -9.81 0);
```
VOF: transportProperties with `phases (water air);` + per-phase nu/rho + `sigma 0.07;`.

## Fluid property quick table (20 C, 1 atm)

| fluid | nu [m2/s] | rho [kg/m3] | misc |
|---|---|---|---|
| air | 1.5e-5 | 1.204 | R=287, gamma=1.4, Pr=0.71, mu=1.82e-5 |
| water | 1.0e-6 | 998 | mu=1.0e-3, sigma(air)=0.072 |
| engine oil | ~9e-5 | 880 | |

## Data-driven field seeding (setFields) - verification and placement

setFields exits 0 even when a region (cylinderToCell/sphereToCell/boxToCell)
matches ZERO cells - e.g. the centre sits inside a baffle/solid, or the mesh has a
hidden scale factor. ALWAYS verify after seeding: the field file must contain
`nonuniform List<scalar>`; parse it and count entries above threshold.

Robust placement recipe (validated on the mixer cases):
1. `postProcess -func writeCellCentres -time 0`  -> writes 0/C (vector field)
2. parse 0/C; for each candidate centre, count cells within the blob radius
3. pick the best candidate (count > ~20), regenerate setFieldsDict with it
4. `setFields`, re-verify the count, then `rm -f 0/C 0/Cx 0/Cy 0/Cz`

## 0.orig restore TRAP (validated across 108 solvers)

`restore0Dir` / `cp -r 0.orig 0` MUST be `rm -rf 0 && cp -r 0.orig 0`. If a `0/`
already exists (e.g. an earlier copy, or a tooling step that pre-created it), a bare
`cp -r 0.orig 0` nests the fields as `0/0.orig/` instead of restoring them. The
solver then FATALs with "Cannot find patchField entry for <patch>" - most often after
createPatch/subsetMesh/splitMeshRegions added a patch the (unrestored) field lacks.

A functionObject that requests fields from the objectRegistry at construction
(`functions { #include "derivedFields" ... }`) FATALs ("request for ... from
objectRegistry") before the run even starts. To just get a solver running, strip them:
`foamDictionary -entry functions -remove system/controlDict || true`.

## Sources of authoritative examples
- `$FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily` - turbulent internal reference.
- `$FOAM_TUTORIALS/incompressible/icoFoam/cavity/cavity` - minimal laminar reference.
- `foamGetDict <name>` copies annotated dicts from etc/; `foamSearch` finds usage across
  tutorials, e.g. `foamSearch $FOAM_TUTORIALS fvSchemes "divSchemes/div(phi,U)"`.
