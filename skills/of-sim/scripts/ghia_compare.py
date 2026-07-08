#!/usr/bin/env python3
"""Compare cavity centerline Ux profile against Ghia et al. (1982), Re=100.

Usage: ghia_compare.py <raw sample file> [<earlier raw file for drift check>]
Raw file columns: y Ux Uy Uz (axis-y uniform line sample, L=0.1 m, Ulid=1 m/s).
"""
import sys

GHIA_RE100 = [  # (y/L, u/Ulid) vertical centerline, 129x129 grid
    (0.0000, 0.00000), (0.0547, -0.03717), (0.0625, -0.04192),
    (0.0703, -0.04775), (0.1016, -0.06434), (0.1719, -0.10150),
    (0.2813, -0.15662), (0.4531, -0.21090), (0.5000, -0.20581),
    (0.6172, -0.13641), (0.7344, 0.00332), (0.8516, 0.23151),
    (0.9531, 0.68717), (0.9609, 0.73722), (0.9688, 0.78871),
    (0.9766, 0.84123), (1.0000, 1.00000),
]
L = 0.1


def load_profile(path):
    pts = []
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) >= 2:
                try:
                    pts.append((float(parts[0]) / L, float(parts[1])))
                except ValueError:
                    pass
    pts.sort()
    return pts


def interp(pts, x):
    if x <= pts[0][0]:
        return pts[0][1]
    if x >= pts[-1][0]:
        return pts[-1][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x0 <= x <= x1:
            w = (x - x0) / (x1 - x0) if x1 > x0 else 0.0
            return y0 + w * (y1 - y0)
    return pts[-1][1]


def main():
    sim = load_profile(sys.argv[1])
    print(f"{'y/L':>8} {'Ghia':>10} {'sim':>10} {'abs.err':>9}")
    errs = []
    for y, u_ref in GHIA_RE100:
        u_sim = interp(sim, y)
        err = abs(u_sim - u_ref)
        errs.append(err)
        print(f"{y:8.4f} {u_ref:10.5f} {u_sim:10.5f} {err:9.5f}")
    rms = (sum(e * e for e in errs) / len(errs)) ** 0.5
    print(f"max_abs_err={max(errs):.5f}  rms_err={rms:.5f}  n={len(errs)}")

    if len(sys.argv) > 2:  # steadiness drift between two times
        prev = load_profile(sys.argv[2])
        drift = max(abs(interp(prev, y) - interp(sim, y)) for y, _ in GHIA_RE100)
        print(f"steadiness_drift={drift:.6f}")

    ok = max(errs) < 0.03
    print("GHIA_VALIDATION=" + ("PASS" if ok else "FAIL"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
