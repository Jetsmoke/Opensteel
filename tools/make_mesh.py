#!/usr/bin/env python3
"""Turn the Aerox 9 STL scan into model/Aerox9.mesh for Opensteel.

The scan is one solid surface, and too noisy at the key edges to show clean key
shapes. So this welds it into a smooth indexed mesh for the body, then uses it only
to measure each of the 12 side keys: where its top face is, which way it faces, and
the size and slant of its parallelogram. The app draws clean caps from those.

Usage: tools/make_mesh.py model/Aerox9.stl model/Aerox9.mesh

Output (little-endian):
    b"OSM2", u32 vertex count V, u32 triangle count T
    V × 3 f32 positions (mm; z up, front at -y, side grid on +x)
    V × 3 f32 normals
    T × 3 u32 indices (the body only; the scan's key tops are left out)
    12 × key caps, keys 1…12, each 15 f32:
        centre of the top face (3), along the key (3), up the key (3), facing out (3),
        width, height, lean (how far the sides shift along per unit up)
"""
import math
import os
import struct
import sys
from collections import defaultdict

# Key centres (y, z) in mm, measured from a scaled side render; row 0 is the top row.
ROWS = [
    ([-25.9, -16.1, -5.6, 4.2], [21.0, 22.4, 23.6, 24.8], 7.3),
    ([-23.4, -12.6, -1.4, 9.4], [15.7, 16.4, 17.1, 17.7], 3.4),
    ([-19.9, -9.1, 1.7, 11.9], [8.7, 8.9, 9.1, 9.3], 1.0),
]
HALF_LENGTH, HALF_HEIGHT = 5.6, 2.7   # a key cell, slightly larger than the key
GROOVE_DEPTH = 0.85  # mm below a key's top face where the groove starts
# How far (in cell sizes) a key may grow. Key 10 sits against the panel's raised rim,
# which is as high as the keys, so it gets a tighter limit.
GROWTH_LIMIT = {10: 1.15}
PANEL_NORMAL = (0.97, 0.01, -0.03)
# Height map of the side panel used to measure the keys: 0.2 mm cells over y × z.
CELL, Y0, Z0 = 0.2, -38.0, 0.0
COLS_Y, ROWS_Z = 330, 160
RAISE = 0.15   # mm above the panel's local curve that counts as the top of a key
ERODE = 5      # cells shaved off plateaus so neighbouring keys separate


def side_number(column, row):
    return column * 3 + (2 - row) + 1


def norm(v):
    length = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2) or 1.0
    return (v[0] / length, v[1] / length, v[2] / length)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def load(path):
    data = open(path, 'rb').read()
    count = struct.unpack('<I', data[80:84])[0]
    index, positions, triangles = {}, [], []
    for i in range(count):
        values = struct.unpack('<9f', data[84 + 50 * i + 12:84 + 50 * i + 48])
        tri = []
        for k in range(3):
            p = values[3 * k:3 * k + 3]
            key = (round(p[0], 4), round(p[1], 4), round(p[2], 4))
            if key not in index:
                index[key] = len(positions)
                positions.append(p)
            tri.append(index[key])
        if len(set(tri)) == 3:
            triangles.append(tuple(tri))
    return positions, triangles


def vertex_normals(positions, triangles):
    sums = [[0.0, 0.0, 0.0] for _ in positions]
    for a, b, c in triangles:
        n = cross(sub(positions[b], positions[a]), sub(positions[c], positions[a]))  # area-weighted
        for v in (a, b, c):
            sums[v][0] += n[0]; sums[v][1] += n[1]; sums[v][2] += n[2]
    return [norm(s) for s in sums]


def label_keys(positions, triangles):
    """Work out which triangles are the top of each side key.

    1. Grow all 12 keys outward from their centres at once, so each key claims the
       part of the panel nearest to it along the surface.
    2. Fit a plane to each key's top face and drop whatever sits more than
       GROOVE_DEPTH below it: that is the groove between keys, which stays black.
    """
    panel = norm(PANEL_NORMAL)
    centres = [tuple((positions[a][k] + positions[b][k] + positions[c][k]) / 3 for k in range(3))
               for a, b, c in triangles]
    depth = [dot(c, panel) for c in centres]
    side = [t for t in range(len(triangles)) if centres[t][0] > 22]

    by_edge = defaultdict(list)
    for t in side:
        a, b, c = triangles[t]
        for e in ((a, b), (b, c), (c, a)):
            by_edge[tuple(sorted(e))].append(t)

    def neighbours(t):
        a, b, c = triangles[t]
        for e in ((a, b), (b, c), (c, a)):
            for other in by_edge[tuple(sorted(e))]:
                if other != t:
                    yield other

    # Step 1: simultaneous growth from every key's centre, kept inside a loose cell.
    cells = {}
    for row, (ys, zs, rise) in enumerate(ROWS):
        angle = math.radians(rise)
        for column in range(4):
            cells[side_number(column, row)] = (ys[column], zs[column], math.cos(angle), math.sin(angle))

    def reach(t, number):
        y, z, cos_r, sin_r = cells[number]
        dy, dz = centres[t][1] - y, centres[t][2] - z
        along, across = dy * cos_r + dz * sin_r, -dy * sin_r + dz * cos_r
        return max(abs(along) / HALF_LENGTH, abs(across) / HALF_HEIGHT)

    labels = bytearray(len(triangles))
    frontier = []
    for number in cells:
        near = [t for t in side if reach(t, number) < 0.25]
        top = max(depth[t] for t in near)
        face = [t for t in near if depth[t] > top - 0.6]
        y, z = cells[number][:2]
        seed = min(face, key=lambda t: (centres[t][1] - y) ** 2 + (centres[t][2] - z) ** 2)
        labels[seed] = number
        frontier.append(seed)
    while frontier:  # breadth-first, so neighbouring keys meet halfway
        next_frontier = []
        for t in frontier:
            for other in neighbours(t):
                if not labels[other] and reach(other, labels[t]) < GROWTH_LIMIT.get(labels[t], 1.3):
                    labels[other] = labels[t]
                    next_frontier.append(other)
        frontier = next_frontier

    # Step 2: keep only what sits on each key's top face.
    for number in cells:
        mine = [t for t in side if labels[t] == number]
        ranked = sorted(mine, key=lambda t: depth[t])
        upper = ranked[len(ranked) // 2:]
        plane = fit_plane([(centres[t][1], centres[t][2], depth[t]) for t in upper])
        for t in mine:
            expected = plane[0] + plane[1] * centres[t][1] + plane[2] * centres[t][2]
            if depth[t] < expected - GROOVE_DEPTH:
                labels[t] = 0

    # Tidy up: each key keeps its largest connected patch, then pinholes are filled.
    for number in cells:
        pieces, seen = [], set()
        for start in side:
            if labels[start] != number or start in seen:
                continue
            piece, stack = [], [start]
            seen.add(start)
            while stack:
                t = stack.pop()
                piece.append(t)
                for other in neighbours(t):
                    if other not in seen and labels[other] == number:
                        seen.add(other)
                        stack.append(other)
            pieces.append(piece)
        pieces.sort(key=len, reverse=True)
        for piece in pieces[1:]:
            for t in piece:
                labels[t] = 0
    # Smooth ragged edges: a triangle follows the majority of its neighbours.
    for _ in range(4):
        changes = []
        for t in side:
            around = [labels[o] for o in neighbours(t)]
            if len(around) < 3:
                continue
            for value in set(around):
                if value != labels[t] and around.count(value) >= 2:
                    changes.append((t, value))
                    break
        for t, value in changes:
            labels[t] = value
    return labels


def fit_plane(samples):
    """Least-squares d = a + b·y + c·z through (y, z, d) samples."""
    n = float(len(samples))
    sy = sum(s[0] for s in samples); sz = sum(s[1] for s in samples); sd = sum(s[2] for s in samples)
    syy = sum(s[0] * s[0] for s in samples); szz = sum(s[1] * s[1] for s in samples)
    syz = sum(s[0] * s[1] for s in samples)
    syd = sum(s[0] * s[2] for s in samples); szd = sum(s[1] * s[2] for s in samples)
    m = [[n, sy, sz], [sy, syy, syz], [sz, syz, szz]]
    v = [sd, syd, szd]

    def det(a):
        return (a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
                - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]))
    d = det(m)
    result = []
    for col in range(3):  # Cramer's rule
        replaced = [row[:] for row in m]
        for r in range(3):
            replaced[r][col] = v[r]
        result.append(det(replaced) / d)
    return result


def height_map(positions, triangles):
    """Rasterise the side panel seen straight on: cell (i, j) holds how far out (x, mm)
    the surface is at y = Y0 + i·CELL, z = Z0 + j·CELL. None where there is no surface."""
    grid = [[None] * ROWS_Z for _ in range(COLS_Y)]
    for tri in triangles:
        p = [positions[v] for v in tri]
        if min(q[0] for q in p) < 20:
            continue
        ys, zs = [q[1] for q in p], [q[2] for q in p]
        i0, i1 = max(0, int((min(ys) - Y0) / CELL)), min(COLS_Y - 1, int((max(ys) - Y0) / CELL) + 1)
        j0, j1 = max(0, int((min(zs) - Z0) / CELL)), min(ROWS_Z - 1, int((max(zs) - Z0) / CELL) + 1)
        (ay, az), (by, bz), (cy, cz) = [(q[1], q[2]) for q in p]
        area = (by - ay) * (cz - az) - (cy - ay) * (bz - az)
        if abs(area) < 1e-9:
            continue
        for i in range(i0, i1 + 1):
            y = Y0 + i * CELL
            for j in range(j0, j1 + 1):
                z = Z0 + j * CELL
                w1 = ((by - y) * (cz - z) - (cy - y) * (bz - z)) / area
                w2 = ((cy - y) * (az - z) - (ay - y) * (cz - z)) / area
                w3 = 1 - w1 - w2
                if w1 < -1e-6 or w2 < -1e-6 or w3 < -1e-6:
                    continue
                x = w1 * p[0][0] + w2 * p[1][0] + w3 * p[2][0]
                if grid[i][j] is None or x > grid[i][j]:
                    grid[i][j] = x
    return grid


def box_blur(grid, radius):
    """Mean over a (2·radius+1)² window, ignoring empty cells."""
    out = [[None] * ROWS_Z for _ in range(COLS_Y)]
    for i in range(COLS_Y):
        for j in range(ROWS_Z):
            total, count = 0.0, 0
            for a in range(max(0, i - radius), min(COLS_Y, i + radius + 1), 2):
                for b in range(max(0, j - radius), min(ROWS_Z, j + radius + 1), 2):
                    if grid[a][b] is not None:
                        total += grid[a][b]; count += 1
            out[i][j] = total / count if count else None
    return out


def measure_keys(positions, triangles, debug_dir=None):
    """Fit the 12 keys as one regular grid of identical caps.

    The side panel becomes a height map; with its gentle curve removed, keys are raised
    plateaus and grooves are low lines. The 12 plateaus give unbiased key centres and
    sizes. A lattice centre(column, row) = O + column·A + row·B through those centres
    gives every key one size, angle and slant (sides follow the column direction B).
    """
    height = height_map(positions, triangles)
    background = box_blur(height, int(4.0 / CELL))
    raised = [[height[i][j] is not None and background[i][j] is not None
               and height[i][j] - background[i][j] > RAISE for j in range(ROWS_Z)] for i in range(COLS_Y)]
    # Erode a little so keys touching through shallow spots come apart.
    for _ in range(ERODE):
        raised = [[raised[i][j] and all(0 <= i + di < COLS_Y and 0 <= j + dj < ROWS_Z and raised[i + di][j + dj]
                                        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                   for j in range(ROWS_Z)] for i in range(COLS_Y)]

    if debug_dir:
        write_debug(debug_dir, height, background, raised, None, 0, 0)

    # Connected plateaus near each expected key centre.
    seen = [[False] * ROWS_Z for _ in range(COLS_Y)]
    blobs = []
    for i in range(COLS_Y):
        for j in range(ROWS_Z):
            if raised[i][j] and not seen[i][j]:
                cells, stack = [], [(i, j)]
                seen[i][j] = True
                while stack:
                    a, b = stack.pop()
                    cells.append((a, b))
                    for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        c, d = a + da, b + db
                        if 0 <= c < COLS_Y and 0 <= d < ROWS_Z and raised[c][d] and not seen[c][d]:
                            seen[c][d] = True
                            stack.append((c, d))
                blobs.append(cells)
    found = {}
    for row, (ys, zs, rise) in enumerate(ROWS):
        for column in range(4):
            y, z = ys[column], zs[column]
            best = None
            for cells in blobs:
                if len(cells) < 200:
                    continue
                cy = Y0 + CELL * sum(c[0] for c in cells) / len(cells)
                cz = Z0 + CELL * sum(c[1] for c in cells) / len(cells)
                distance = (cy - y) ** 2 + (cz - z) ** 2
                if distance < 16 and (best is None or distance < best[0]):
                    best = (distance, cells, cy, cz)
            if best is None:
                raise SystemExit('no plateau found for key %d' % side_number(column, row))
            found[side_number(column, row)] = (column, 2 - row, best[1], best[2], best[3])

    # The grid fans slightly (the side is curved, and the top row rises more than the
    # bottom), so fit a smooth bilinear grid through the 12 plateau centres:
    #   centre(s, t) = O + s·A + t·B + s·t·C   (s = column, t = row counting up)
    samples = list(found.values())
    rows_ls = [[1.0, s[0], s[1], s[0] * s[1]] for s in samples]
    def least_squares(values):
        m = [[sum(r[a] * r[b] for r in rows_ls) for b in range(4)] for a in range(4)]
        return solve(m, [sum(r[a] * v for r, v in zip(rows_ls, values)) for a in range(4)])
    gy = least_squares([s[3] for s in samples])
    gz = least_squares([s[4] for s in samples])

    def grid(s, t):
        return (gy[0] + gy[1] * s + gy[2] * t + gy[3] * s * t, gz[0] + gz[1] * s + gz[2] * t + gz[3] * s * t)

    def steps(s, t):  # local column step A and row step B, in (y, z)
        return (gy[1] + gy[3] * t, gz[1] + gz[3] * t), (gy[2] + gy[3] * s, gz[2] + gz[3] * s)

    # Key size in grid steps, measured where the surface is halfway between the key's
    # top and the groove floor (the edge of a rounded profile), walking out from each centre.
    def relief(s, t):
        y, z = grid(s, t)
        i, j = int(round((y - Y0) / CELL)), int(round((z - Z0) / CELL))
        if 0 <= i < COLS_Y and 0 <= j < ROWS_Z and height[i][j] is not None and background[i][j] is not None:
            return height[i][j] - background[i][j]
        return None

    def edge(column, grid_row, ds, dt):
        reaches = []
        for off in (-0.2, -0.1, 0.0, 0.1, 0.2):
            s0, t0 = column + off * dt, grid_row + off * ds
            line = [relief(s0 + k * 0.01 * ds, t0 + k * 0.01 * dt) for k in range(0, 61)]
            line = [x for x in line if x is not None]
            if len(line) < 40:
                continue
            top, floor = sorted(line[:15])[7], min(line)
            for k, x in enumerate(line):
                if x < (top + floor) / 2:
                    reaches.append(k * 0.01)
                    break
        return sorted(reaches)[len(reaches) // 2] if reaches else None

    spans_s, spans_t = [], []
    for column, grid_row, cells, cy, cz in samples:
        right, left = edge(column, grid_row, 1, 0), edge(column, grid_row, -1, 0)
        up, down = edge(column, grid_row, 0, 1), edge(column, grid_row, 0, -1)
        if right and left:
            spans_s.append(right + left)
        if up and down:
            spans_t.append(up + down)
    spans_s.sort(); spans_t.sort()
    span_s, span_t = spans_s[len(spans_s) // 2], spans_t[len(spans_t) // 2]

    # Lift into 3D on a smooth curved surface through the key tops:
    #   x = q0 + q1·y + q2·z + q3·y² + q4·y·z + q5·z²
    tops = []
    for column, grid_row, cells, cy, cz in samples:
        values = sorted(height[c[0]][c[1]] for c in cells)
        y, z = grid(column, grid_row)
        tops.append((y, z, values[len(values) * 3 // 4]))
    basis = [[1.0, y, z, y * y, y * z, z * z] for y, z, _ in tops]
    q = solve([[sum(b[a] * b[c] for b in basis) for c in range(6)] for a in range(6)],
              [sum(b[a] * tp[2] for b, tp in zip(basis, tops)) for a in range(6)])

    caps = {}
    for number, (column, grid_row, cells, cy, cz) in found.items():
        y, z = grid(column, grid_row)
        x = q[0] + q[1] * y + q[2] * z + q[3] * y * y + q[4] * y * z + q[5] * z * z
        slope_y, slope_z = q[1] + 2 * q[3] * y + q[4] * z, q[2] + q[4] * y + 2 * q[5] * z
        facing = norm((1.0, -slope_y, -slope_z))
        (ay, az), (by, bz) = steps(column, grid_row)
        A3 = (slope_y * ay + slope_z * az, ay, az)
        B3 = (slope_y * by + slope_z * bz, by, bz)
        u = norm(sub(A3, tuple(facing[k] * dot(A3, facing) for k in range(3))))
        v = cross(facing, u)
        caps[number] = ((x, y, z), u, v, facing,
                        span_s * dot(A3, u), span_t * dot(B3, v), dot(B3, u) / dot(B3, v))
    # The real keys are identical: give every cap the median size. Position, angle and
    # slant stay per key, so each cap still follows the grooves around it.
    widths = sorted(c[4] for c in caps.values()); heights = sorted(c[5] for c in caps.values())
    width, height_mm = widths[len(widths) // 2], heights[len(heights) // 2]
    for number, c in caps.items():
        caps[number] = c[:4] + (width, height_mm, c[6])
    print('keys %.2f x %.2f mm (measured %.2f-%.2f x %.2f-%.2f), slant %.2f to %.2f'
          % (width, height_mm, widths[0], widths[-1], heights[0], heights[-1],
             min(c[6] for c in caps.values()), max(c[6] for c in caps.values())))
    if debug_dir:
        write_debug(debug_dir, height, background, raised, grid, span_s, span_t)
    return caps


def write_debug(directory, height, background, raised, grid, span_s, span_t):
    """Grey = raised above the panel's curve, white = plateau, orange = fitted key outlines."""
    pixels = []
    for j in reversed(range(ROWS_Z)):
        for i in range(COLS_Y):
            h, b = height[i][j], background[i][j]
            level = 0 if h is None or b is None else max(0, min(255, int(128 + (h - b) * 200)))
            pixels.append((255, 255, 255) if raised[i][j] else (level, level, level))

    def plot(y, z):
        i, j = int(round((y - Y0) / CELL)), int(round((z - Z0) / CELL))
        if 0 <= i < COLS_Y and 0 <= j < ROWS_Z:
            pixels[(ROWS_Z - 1 - j) * COLS_Y + i] = (255, 110, 0)
    for column in range(4 if grid else 0):
        for grid_row in range(3):
            for k in range(400):
                f = k / 400.0
                for s, tt in ((column - span_s / 2 + f * span_s, grid_row - span_t / 2),
                              (column - span_s / 2 + f * span_s, grid_row + span_t / 2),
                              (column - span_s / 2, grid_row - span_t / 2 + f * span_t),
                              (column + span_s / 2, grid_row - span_t / 2 + f * span_t)):
                    plot(*grid(s, tt))
    with open(directory + '/keys.ppm', 'wb') as out:
        out.write(b'P6 %d %d 255\n' % (COLS_Y, ROWS_Z))
        out.write(bytes(c for p in pixels for c in p))


def solve(m, rhs):
    """Gaussian elimination with partial pivoting for a small dense system."""
    n = len(rhs)
    a = [row[:] + [rhs[i]] for i, row in enumerate(m)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(a[r][col]))
        a[col], a[pivot] = a[pivot], a[col]
        for r in range(n):
            if r != col:
                factor = a[r][col] / a[col][col]
                for c in range(col, n + 1):
                    a[r][c] -= factor * a[col][c]
    return [a[i][n] / a[i][i] for i in range(n)]


def main(source, target):
    positions, triangles = load(source)
    normals = vertex_normals(positions, triangles)
    labels = label_keys(positions, triangles)
    caps = measure_keys(positions, triangles, debug_dir=os.environ.get('OPENSTEEL_DEBUG_DIR'))
    # The scan's key tops are cut out: they are scooped and would poke through the caps.
    body = [tri for t, tri in enumerate(triangles) if not labels[t]]
    with open(target, 'wb') as out:
        out.write(b'OSM2' + struct.pack('<II', len(positions), len(body)))
        out.write(b''.join(struct.pack('<3f', *p) for p in positions))
        out.write(b''.join(struct.pack('<3f', *n) for n in normals))
        out.write(b''.join(struct.pack('<3I', *t) for t in body))
        for number in range(1, 13):
            centre, u, v, facing, width, height, lean = caps[number]
            out.write(struct.pack('<15f', *centre, *u, *v, *facing, width, height, lean))
            print('key %2d: %.1f x %.1f mm at (%.1f, %.1f, %.1f)' % (number, width, height, *centre))
    print('%d vertices, %d body triangles' % (len(positions), len(body)))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
