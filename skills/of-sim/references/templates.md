# Curated scenario -> template map (paths verified against v2412 tutorials)

Clone with: `ofcase.sh new <relative path under tutorials/> <new-name>`
Read the template's Allrun first if present - it encodes the intended mesh/run sequence.

## Incompressible
| scenario | template (tutorials/...) | notes |
|---|---|---|
| Lid-driven cavity, laminar 2D | incompressible/icoFoam/cavity/cavity | 20x20, Re=10; nu/U edit for other Re |
| Backward-facing step, steady turbulent | incompressible/simpleFoam/pitzDaily | kEpsilon default; 12k cells; converges ~300 iters |
| Step, transient turbulent | incompressible/pisoFoam/RAS/cavity or pimpleFoam variants | |
| Airfoil external aero | incompressible/simpleFoam/airFoil2D | SpalartAllmaras; mapped mesh |
| Full external aero from STL | incompressible/simpleFoam/motorBike | snappy workflow + forces; parallel Allrun |
| Pipe/duct bend | incompressible/simpleFoam/squareBend (see compressible analog) | |
| Atmospheric/terrain | incompressible/simpleFoam/turbineSiting, windAroundBuildings | |
| Rotating machinery (MRF) | incompressible/simpleFoam/rotorDisk | fvOptions MRF |
| LES channel/hill | incompressible/pimpleFoam/LES/periodicHill/transient | needs fine mesh |
| Vortex shedding cylinder | incompressible/pimpleFoam/laminar/cylinder2D | Strouhal validation |

## Compressible / heat transfer
| scenario | template | notes |
|---|---|---|
| Subsonic duct/aero steady | compressible/rhoSimpleFoam/squareBend, aerofoilNACA0012 | |
| Transient compressible | compressible/rhoPimpleFoam/RAS/aerofoilNACA0012, TJunctionAverage | |
| Supersonic forward step | compressible/sonicFoam/laminar/forwardStep | Ma 3 classic |
| Shock tube | compressible/rhoCentralFoam/shockTube | Sod benchmark |
| Heated room natural convection | heatTransfer/buoyantBoussinesqSimpleFoam/hotRoom; compressible: buoyantSimpleFoam/comfortHotRoom or hotRadiationRoom | |
| Conjugate heat transfer | heatTransfer/chtMultiRegionSimpleFoam/multiRegionHeaterRadiation; transient: chtMultiRegionFoam/multiRegionHeater | multi-region: -region flags, changeDictionary |
| Electronics cooling | heatTransfer/chtMultiRegionSimpleFoam/cpuCabinet | |

## Multiphase
| scenario | template | notes |
|---|---|---|
| Dam break (VOF classic) | multiphase/interFoam/laminar/damBreak/damBreak | setFields for initial column |
| Dam break + obstacle | multiphase/interFoam/laminar/damBreakWithObstacle | 3D |
| Sharp-interface variants | multiphase/interIsoFoam/damBreakWithObstacle, weirOverflow | |
| Waves/coastal | multiphase/interFoam/laminar/waves/* | waveModels |
| Sloshing tank | multiphase/interFoam/laminar/sloshingTank2D (also 3D, 3DoF/6DoF variants) | mesh motion |
| Bubble column | multiphase/twoPhaseEulerFoam/laminar/bubbleColumn | Euler-Euler; RAS/LES variants + laminar/bubbleColumnIATE exist |

## Basic / verification
| scenario | template | notes |
|---|---|---|
| Heat conduction in solid | basic/laplacianFoam/flange | |
| Passive scalar | basic/scalarTransportFoam/pitzDaily | frozen flux |
| Potential flow | basic/potentialFoam/cylinder | analytic comparison |
| Stress analysis | stressAnalysis/solidDisplacementFoam/plateHole | sigma_xx validation |

## Multi-purpose notes
- `setups.orig`-style templates (periodicHill, planarPoiseuille) are parameterized
  multi-config cases - copy the resolved `setups.orig/common` + specific config.
- Many tutorials ship `Allrun` using RunFunctions (`runApplication`, `runParallel`,
  `restore0Dir`); mirror those steps explicitly via ofrun.sh for controllability.
- Verification suite exists at tutorials/verificationAndValidation (schemes, multiphase,
  turbulentInflow) - good for regression tests of this automation.
