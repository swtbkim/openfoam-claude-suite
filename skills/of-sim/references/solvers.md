# OpenFOAM v2412 solver selection

A standard full v2412 build ships ~290 applications (~88 solvers); this machine's exact
inventory: references/environment.md. Descriptions below are extracted from the v2412
source headers. Tutorial counts indicate template availability
(from `grep application tutorials/**/controlDict`).

## Selection tree

```
START
|- electromagnetics / stress / financial / DSMC? -> niche solvers (bottom table)
|- particles dominate physics? -> lagrangian family (DPMFoam, MPPICFoam, sprayFoam, ...)
|- combustion/reactions? -> reactingFoam, fireFoam, XiFoam, chemFoam
|- more than one fluid phase?
|   |- sharp interface (free surface, sloshing, dam break) -> interFoam (transient VOF)
|   |   |- need sharper interface -> interIsoFoam (isoAdvector)
|   |   |- compressible phases -> compressibleInterFoam
|   |   |- phase change (cavitation) -> interPhaseChangeFoam / cavitatingFoam
|   |- dispersed (bubbles/drops, fluidized bed) -> twoPhaseEulerFoam / multiphaseEulerFoam
|- solid + fluid heat conduction coupled? -> chtMultiRegionFoam (transient) /
|                                            chtMultiRegionSimpleFoam (steady)
|- buoyancy-driven single region?
|   |- small dT, incompressible -> buoyantBoussinesq{Simple,Pimple}Foam
|   |- otherwise -> buoyant{Simple,Pimple}Foam
|- Ma > 0.3 ?
|   |- Ma < ~1, steady -> rhoSimpleFoam ; transient -> rhoPimpleFoam
|   |- transonic/supersonic -> sonicFoam (pressure-based) / rhoCentralFoam (density-based,
|      shocks) ; pure shock benchmarks -> rhoCentralFoam
|- incompressible single phase:
    |- steady -> simpleFoam (laminar or turbulent; SIMPLE/SIMPLEC)
    |- transient, laminar teaching cases -> icoFoam
    |- transient general -> pimpleFoam (large Co via outer correctors; pisoFoam if Co<1)
    |- rotating frame -> SRF*Foam ; porous -> porousSimpleFoam ; non-Newtonian ->
       nonNewtonianIcoFoam or viscosity models in transportProperties
```

## Main solvers (description = source header)

### incompressible (14)
| solver | tutorials | description |
|---|---|---|
| simpleFoam | 32 | Steady-state solver for incompressible, turbulent flows |
| pimpleFoam | 35 | Large time-step transient solver for incompressible turbulent flow (PIMPLE), optional mesh motion |
| pisoFoam | 8 | Transient solver for incompressible turbulent flow (PISO) |
| icoFoam | 11 | Transient solver for incompressible, laminar flow of Newtonian fluids (PISO) |
| nonNewtonianIcoFoam | - | icoFoam + non-Newtonian transport models |
| porousSimpleFoam | 3 | simpleFoam + implicit/explicit porosity treatment |
| SRFSimpleFoam / SRFPimpleFoam | - | single rotating frame steady/transient |
| boundaryFoam | - | 1D steady turbulent flow, generates inlet boundary-layer profiles |
| shallowWaterFoam | - | inviscid shallow-water equations with rotation |
| adjointOptimisationFoam | 89 | automated adjoint-based optimisation loop (shape/topology) |
| adjointShapeOptimizationFoam | - | duct shape optimisation via adjoint blockage |
| overSimpleFoam / overPimpleDyMFoam | - | overset-mesh variants |

### compressible (10)
| solver | tutorials | description |
|---|---|---|
| rhoSimpleFoam | 7 | Steady-state compressible turbulent flow (subsonic/transonic) |
| rhoPimpleFoam | 13 | Transient compressible turbulent flow, HVAC-type, mesh motion |
| rhoPorousSimpleFoam | - | steady compressible + porosity |
| sonicFoam | 4 | transient trans/supersonic gas (pressure-based PISO) |
| sonicLiquidFoam | - | trans/supersonic compressible liquid |
| rhoCentralFoam | 7 | density-based central-upwind (Kurganov-Tadmor) shock solver |
| rhoPimpleAdiabaticFoam | - | weakly compressible low-Ma aeroacoustics |
| sonicDyMFoam / overRho*DyMFoam | - | mesh-motion variants |

### heatTransfer (10)
| solver | tutorials | description |
|---|---|---|
| buoyantSimpleFoam | 7 | steady buoyant turbulent compressible, radiation, ventilation/HT |
| buoyantPimpleFoam | 3 | transient buoyant turbulent compressible |
| buoyantBoussinesqSimpleFoam | 6 | steady buoyant incompressible (Boussinesq) |
| buoyantBoussinesqPimpleFoam | - | transient Boussinesq |
| chtMultiRegionFoam | 12 | transient conjugate heat transfer fluid+solid regions |
| chtMultiRegionSimpleFoam | 5 | steady CHT |
| solidFoam / thermoFoam | - | solid energy only / energy on frozen flow |

### multiphase (62 incl. submodels; key executables)
| solver | tutorials | description |
|---|---|---|
| interFoam | 43 | 2 incompressible immiscible fluids, VOF interface capturing (MULES) |
| interIsoFoam | 14 | VOF via isoAdvector (sharper interface) |
| compressibleInterFoam | 4 | 2 compressible non-isothermal immiscible fluids VOF |
| multiphaseInterFoam | 3 | n immiscible incompressible fluids VOF |
| twoPhaseEulerFoam | 8 | Euler-Euler 2 compressible phases, one dispersed (bubbles/fluidized) |
| reactingTwoPhaseEulerFoam | 17 | Euler-Euler + species/reactions |
| multiphaseEulerFoam | 4 | n compressible phases Euler-Euler |
| driftFluxFoam | 3 | mixture model for settling/slurry |
| cavitatingFoam | - | barotropic cavitation (HEM) |
| interPhaseChangeFoam | - | VOF + phase change (Kunz/Merkle/SchnerrSauer) |
| potentialFreeSurfaceFoam | - | single-phase + wave-height field |
| icoReactingMultiphaseInterFoam | 8 | VOF + melting/evaporation/solidification |

### combustion (12 exec)
reactingFoam (9), fireFoam (6), XiFoam/XiEngineFoam/PDRFoam (premixed), chemFoam (0D chem),
rhoReactingFoam, coldEngineFoam.

### lagrangian (19)
DPMFoam/MPPICFoam (dense particles), kinematicParcelFoam, reactingParcelFoam (16),
sprayFoam, coalChemistryFoam, uncoupledKinematicParcelFoam.

### basic / other
| solver | description |
|---|---|
| laplacianFoam | Laplace (heat conduction) |
| potentialFoam | potential flow (also the standard initializer) |
| scalarTransportFoam | passive scalar on given flux |
| solidDisplacementFoam | linear-elastic small-strain stress (transient) |
| dnsFoam / dsmcFoam / mhdFoam / electrostaticFoam / magneticFoam / financialFoam | niche |

## Turbulence models (standard v2412 build)
- RAS: kOmegaSST (default external/wall-bounded), kEpsilon, realizableKE, RNGkEpsilon,
  kOmega, SpalartAllmaras (aero), kOmegaSSTLM (transition), LRR/SSG (RSM), v2-f family
  (kEpsilonPhitF), EBRSM; incompressible-only extras: kkLOmega, LamBremhorstKE, qZeta...
- LES: Smagorinsky, WALE (walls), kEqn, dynamicKEqn, sigma, DeardorffDiffStress.
- Set in `constant/turbulenceProperties`: `simulationType laminar|RAS|LES`.

## Notes
- ESI fork (.com) v2412: solvers are standalone executables (no foamRun meta-solver).
- Module/plugin availability varies per build (OpenQBMM, adios, cfmesh, avalanche,
  turbulence-community, ...): check references/environment.md - /of-setup records the
  compiled modules and the $FOAM_USER_APPBIN inventory there.
- $FOAM_USER_APPBIN precedes stock bins in PATH: user-built apps SHADOW stock apps of
  the same name.
- Find anything: `foamSearch`, or list stock apps:
  `ofrun.sh sh - 'ls $FOAM_APPBIN | grep -i <term>'`.
