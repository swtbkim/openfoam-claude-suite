# Meshing recipes (v2412): blockMesh, snappyHexMesh, quality gates

## Route 1: template geometry (preferred)
Clone tutorial, keep its mesh dict. Rescale if needed:
`ofrun.sh run <case> transformPoints -scale '(2 2 2)'` (after blockMesh, before fields)
or scale inside blockMeshDict (`scale 0.001;` for mm geometry).

## Route 2: parametric blockMeshDict

Anatomy (v2412 syntax):
```
scale 1;
vertices ( (x y z) ... );                      // index = order, 0-based
blocks ( hex (v0 v1 v2 v3 v4 v5 v6 v7) (Nx Ny Nz) simpleGrading (gx gy gz) );
edges ();
boundary ( <patchName> { type <patch|wall|empty|wedge|symmetry>; faces ((a b c d) ...); } ... );
```
Hex vertex order: v0-v3 = bottom face counter-clockwise viewed from inside (z-min),
v4-v7 = same order top (z-max). x1->x2 = v0->v1 direction, y v0->v3... Use the proven
patterns below instead of deriving.

### Pattern A: 2D rectangular domain (channel / cavity / step variants)
Domain [0,Lx]x[0,Ly], thickness t (1 cell):
```
scale 1;
vertices (
  (0 0 0) ($Lx 0 0) ($Lx $Ly 0) (0 $Ly 0)
  (0 0 $t) ($Lx 0 $t) ($Lx $Ly $t) (0 $Ly $t)
);
blocks ( hex (0 1 2 3 4 5 6 7) ($Nx $Ny 1) simpleGrading (1 $gy 1) );
boundary (
  inlet  { type patch; faces ((0 4 7 3)); }      // x=0 plane
  outlet { type patch; faces ((1 2 6 5)); }      // x=Lx
  bottom { type wall;  faces ((0 1 5 4)); }      // y=0
  top    { type wall;  faces ((3 7 6 2)); }      // y=Ly
  frontAndBack { type empty; faces ((0 3 2 1) (4 5 6 7)); }
);
```
(grading gy e.g. 5 packs cells to bottom wall; use multi-grading for both walls:
`simpleGrading (1 ((0.5 0.5 5)(0.5 0.5 0.2)) 1)`.)
Lid-driven cavity = same with all four sides `wall`, top patch moving via 0/U.

### Pattern B: 3D box duct
Extend Pattern A: Nz real (>1), frontAndBack -> `sideWalls { type wall; ... }` or symmetry.

### Pattern C: axisymmetric pipe (wedge)
5-deg wedge, axis = x; half-width at radius R: half = R*tan(2.5deg).
In practice: clone an axisymmetric tutorial or build wedge via blockMesh with
`wedge` patches front/back + `empty`-> none; for quick pipe flow prefer Pattern A as a
2D planar channel approximation or a full 3D cylinder via snappy. Search:
`foamSearch $FOAM_TUTORIALS blockMeshDict boundary/type wedge` for live examples.

### Cell sizing
- Target count: quick-look <50k, standard 100k-500k, high >1M (parallel).
- Wall-function RAS: first-cell-center y+ 30-100:
  `Cf ~ 0.026*Re^(-1/7); utau = U*sqrt(Cf/2); y1 = yplus*nu/utau` (y1 = 2*center height).
- Resolve shear layers: >=10 cells across gaps/steps; expansion ratio <= 1.2 near walls.

## Route 3: snappyHexMesh from STL (motorBike workflow)

```
mkdir -p <case>/constant/triSurface  && cp <stl> <case>/constant/triSurface/body.stl
ofrun.sh run <case> surfaceFeatureExtract          # needs system/surfaceFeatureExtractDict
ofrun.sh run <case> blockMesh                      # background hex, cell size = base
# parallel: write decomposeParDict (scotch, N), then
ofrun.sh run <case> decomposePar
ofrun.sh par <case> N snappyHexMesh -overwrite
ofrun.sh par <case> N checkMesh -writeFields '(nonOrthoAngle)' -constant
# fields: restore 0/ AFTER meshing (snappy changes patches); then run solver in parallel
ofrun.sh run <case> reconstructParMesh -constant   # when done
```
snappyHexMeshDict essentials: castellatedMesh+snap on; addLayers optional (3-5 layers,
expansion 1.2, finalLayerThickness 0.3, minThickness 0.1); geometry{ body.stl { type
triSurfaceMesh; name body; } }; refinement surface level (2 3); locationInMesh MUST be
inside fluid; resolveFeatureAngle 30. Template: clone
`incompressible/simpleFoam/motorBike` and read its Allrun + snappyHexMeshDict.

FreeCAD geometry path (if mcp__freecad__ tools connected): create_document ->
primitives/booleans (create_object) -> export STL via execute_code:
`Mesh.export([obj], "/tmp/body.stl")` then copy into constant/triSurface (Windows-host
FreeCAD: export to C:\... and copy via /mnt/c).

## Route 4: rotating-zone AMI mesh (snappy faceZone -> createPatch; validated on 3D mixer)

Sliding-mesh rotating machinery, propeller-tutorial workflow:
1. Add a CLOSED zone surface (cylinder STL enclosing the rotor with clearance both
   to blade tips and to stator/baffles) to snappy `geometry`.
2. refinementSurfaces entry for it:
   ```
   <zoneGeom> { level (2 2); faceType boundary;
                cellZone rotating; faceZone rotating; cellZoneInside inside; }
   ```
   plus `refinementRegions { <zoneGeom> { mode inside; levels ((1e15 1)); } }`
   and `allowFreeStandingZoneFaces false;`.
3. TRAP: snappy names the resulting boundary patch pair after the GEOMETRY name
   (`<geomName>` / `<geomName>_slave`), NOT the faceZone name. createPatchDict must
   reference those and convert to a cyclicAMI pair:
   ```
   { name AMI1; patchInfo { type cyclicAMI; matchTolerance 1e-4;
       neighbourPatch AMI2; transform noOrdering; }
     constructFrom patches; patches (<geomName>); }
   { name AMI2; ... patches (<geomName>_slave); }
   ```
4. Order: blockMesh -> snappyHexMesh -overwrite -> `rm -f 0/cellLevel 0/pointLevel`
   -> createPatch -overwrite -> checkMesh (gate: Mesh OK AND bounding box vs spec)
   -> renumberMesh -overwrite.
5. constant/dynamicMeshDict: dynamicMotionSolverFvMesh + solidBody rotatingMotion
   on the cellZone; ALWAYS ramp omega (numerics.md rotating preset). Verify
   `AMI: ... sum(weights)` ~ 1.0 in the first solver log.
6. Every 0/ field needs entries for all wall patches AND AMI1/AMI2 (cyclicAMI).
   The shaft may pierce the lid and the zone top face - snappy trims it cleanly.

### FreeCAD via MCP - validated specifics
- Model with numeric values equal to METERS (FreeCAD's nominal unit is mm, but STL
  is unitless and OpenFOAM reads coordinates as metres - no rescaling needed).
- Export per-role solids as SEPARATE STLs (vessel / baffles / rotor / zone
  cylinder): `MeshPart.meshFromShape(Shape=s, LinearDeflection=0.003..0.005,
  AngularDeflection=0.3, Relative=False)` then `mesh.write(path)`.
  Binary STL output is fine for OpenFOAM triSurfaceMesh.
- Boolean-fuse blades+hub+shaft into ONE rotor solid.
- Save the .FCStd document so the geometry stays parametric for sweeps.

## Quality gates (checkMesh)

| metric | OK | acceptable | act |
|---|---|---|---|
| max non-orthogonality | <65 | 65-75 (add nNonOrthogonalCorrectors 1-2, limited 0.33 laplacian) | >75 fix mesh |
| max skewness | <2 | 2-4 | >4 fix |
| max aspect ratio | <100 | <1000 (boundary layers fine) | check solver |
| negative volume / non-closed | never | - | always fix |

"Mesh OK" required to proceed. Failed faces -> visualize: `foamToVTK -faceSet <set>`.
2D mesh MUST be 1 cell thick with empty patches; checkMesh reports "1 geometric dimension".
