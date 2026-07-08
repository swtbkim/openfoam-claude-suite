#!/usr/bin/env python3
"""Backward-facing step reattachment from a lowerWall wallShearStress patch sample.

Self-calibrating sign convention: the 'forward flow' sign of tau_x is taken from
the far-downstream 10% of the wall (attached flow by construction). The main
recirculation is the LONGEST contiguous stretch of the opposite sign; the
reattachment point is the crossing at its downstream end. The first opposite-
sign-to-forward transition near the step is the secondary corner vortex edge.
Usage: val-step15-reattach.py <wallShearStress_lower.raw>
"""
import sys

rows = []
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) >= 6 and not line.startswith('#'):
        try:
            x, y, tx = float(p[0]), float(p[1]), float(p[3])
        except ValueError:
            continue
        if y < -0.024:  # bottom wall downstream of step (step base y=-0.0254)
            rows.append((x, tx))
rows.sort()
if not rows:
    print("REATTACHMENT not found (no wall rows)")
    sys.exit(1)

tail = rows[int(len(rows) * 0.9):]
fwd_sign = 1.0 if sum(1 for _, t in tail if t > 0) > len(tail) / 2 else -1.0
print(f"forward-flow tau_x sign (calibrated on last 10% of wall): {'+' if fwd_sign>0 else '-'}")

# recirculation = stretches where tau_x has the OPPOSITE sign to forward flow
stretches = []
i, n = 0, len(rows)
while i < n:
    if rows[i][1] * fwd_sign < 0.0:
        j = i
        while j + 1 < n and rows[j + 1][1] * fwd_sign < 0.0:
            j += 1
        x_start = rows[i][0]
        if j + 1 < n:
            x0, t0 = rows[j]
            x1, t1 = rows[j + 1]
            x_end = x0 + (x1 - x0) * (0.0 - t0) / (t1 - t0)
        else:
            x_end = None
        stretches.append((x_start, x_end, (x_end if x_end is not None else rows[j][0]) - x_start))
        i = j + 1
    else:
        i += 1

h = 0.0254
for s in stretches:
    end = f"{s[1]:.4f}" if s[1] is not None else "open"
    print(f"reversed-flow stretch: x={s[0]:.4f} -> {end} (len={s[2]:.4f} m)")

closed = [s for s in stretches if s[1] is not None]
if closed:
    main = max(closed, key=lambda s: s[2])
    print(f"REATTACHMENT x={main[1]:.4f} m  x/h={main[1]/h:.2f} (step h={h} m)")
else:
    print("REATTACHMENT not found")
