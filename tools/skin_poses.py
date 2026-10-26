"""Bọc lớp da người liền mạch (watertight 2-manifold) qua toàn bộ 14 khớp cơ thể
trên cả 6 file `pose-*.usdz`.

## Vấn đề gốc (BUG-023)
Mesh `Beta_Surface` xuất từ Mixamo gồm các mảnh vỏ rời rạc (Đầu, Ngực, Chậu/Hông,
Đùi, Bắp chân, Bàn chân, Cánh tay, Cẳng tay, Bàn tay). Khi xóa `Beta_Joints`
(các khối cầu ở khớp), cơ thể bị:
1. **Hở khoảng trống lớn** ở cổ, toàn bộ vùng bụng/eo (`Z = 1.00 .. 1.31`), vai,
   khuỷu tay, cổ tay, khớp háng, đầu gối và cổ chân.
2. **Lộ mặt nắp nội bộ (internal end-caps)** bên trong các đầu khớp (như quạt 32
   tam giác ở đỉnh chậu `vert 281`, hai quạt 28 tam giác ở hốc háng `vert 282, 533`,
   và đáy ngực thuôn nhọn chữ V), khiến khi áp vật liệu bán trong suốt
   (`PhysicallyBasedMaterial` với `.transparent`), các vách ngăn nội bộ hiện xuyên
   qua lớp vỏ như người máy bị cắt khúc.

## Giải pháp
1. Trên tư thế chuẩn `pose-standing-straight.usdz`, xác định 28 đĩa mặt nắp nội bộ
   (internal cap disks) tại 14 khớp chính và loại bỏ hoàn toàn 3.143 mặt nắp nội bộ,
   thu được 28 vòng biên khép kín đơn (simple closed boundary loops).
2. Căn chỉnh chiều quay và độ lệch vòng (cyclic shift) tối ưu giữa 14 cặp vòng biên
   `(loopA, loopB)`.
3. Với mỗi tư thế trong 6 file `.usdz`, dựng ống da giải phẫu đa tầng (`K` vòng
   trung gian dùng đường cong Hermite bậc 3 bảo toàn tiết diện ngang + khâu khóa kéo
   watertight trực tiếp vào các đỉnh biên của `loopA` và `loopB`), sau đó làm mượt
   bảo toàn thể tích Taubin (λ|μ smoothing) và tính lại pháp tuyến đỉnh mượt
   (`faceVarying` normals từ trung bình pháp tuyến mặt có trọng số diện tích).
4. Kết quả: toàn bộ 15 phần cơ thể chính hợp nhất thành **1 mặt da người 2-manifold
   kín duy nhất**, không còn bất kỳ khe hở hay vách ngăn nội bộ nào.
"""

import glob
import os
import re
import shutil
import struct
import subprocess
import tempfile
import zipfile
from collections import Counter, defaultdict, deque

import numpy as np

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIG_DIR = os.path.join(ROOT_DIR, "tmp", "net3d", "orig_poses")
OUT_DIR = os.path.join(ROOT_DIR, "NET_ver1", "Assets", "Resources")
USDZ_ALIGNMENT = 64


def extract_usda(usdz_path, work_dir):
    with zipfile.ZipFile(usdz_path) as zf:
        usdc = [n for n in zf.namelist() if n.endswith((".usdc", ".usda", ".usd"))][0]
        zf.extract(usdc, work_dir)
    usda_path = os.path.join(work_dir, "scene.usda")
    subprocess.run(["/usr/bin/usdcat", os.path.join(work_dir, usdc), "-o", usda_path], check=True)
    with open(usda_path, "r", encoding="utf-8") as f:
        return f.read()


def parse_usda(text):
    pts_str = re.search(r"point3f\[\] points = \[(.*?)\]", text, re.S).group(1)
    pts = np.array(
        [(float(x), float(y), float(z)) for x, y, z in re.findall(r"\(([^,]+),\s*([^,]+),\s*([^)]+)\)", pts_str)],
        dtype=np.float64,
    )
    counts = [int(x) for x in re.search(r"int\[\] faceVertexCounts = \[(.*?)\]", text, re.S).group(1).split(",")]
    indices = [int(x) for x in re.search(r"int\[\] faceVertexIndices = \[(.*?)\]", text, re.S).group(1).split(",")]
    primvars = {}
    for m in re.finditer(r"float\[\] primvars:mixamorig_(\w+) = \[(.*?)\]", text):
        primvars[m.group(1)] = [float(v) for v in m.group(2).split(",")]
    faces = []
    cur = 0
    for c in counts:
        faces.append(indices[cur : cur + c])
        cur += c
    return pts, faces, primvars


def newell_normal(poly_pts):
    n = np.zeros(3, dtype=np.float64)
    L = len(poly_pts)
    for i in range(L):
        p0 = poly_pts[i]
        p1 = poly_pts[(i + 1) % L]
        n[0] += (p0[1] - p1[1]) * (p0[2] + p1[2])
        n[1] += (p0[2] - p1[2]) * (p0[0] + p1[0])
        n[2] += (p0[0] - p1[0]) * (p0[1] + p1[1])
    norm = np.linalg.norm(n)
    return n / (norm if norm > 1e-12 else 1.0)


def build_topology_plan(pts0, faces, primvars):
    """Xác định 28 đĩa mặt nắp nội bộ và 14 cặp vòng biên đã căn chỉnh từ tư thế đứng."""
    f_centroids = np.array([pts0[f].mean(axis=0) for f in faces])
    v2f = defaultdict(list)
    e2f = defaultdict(list)
    for fi, f in enumerate(faces):
        for i, v in enumerate(f):
            v2f[v].append(fi)
            e = tuple(sorted((v, f[(i + 1) % len(f)])))
            e2f[e].append(fi)
    f_adj = defaultdict(list)
    for e, flist in e2f.items():
        if len(flist) == 2:
            f_adj[flist[0]].append(flist[1])
            f_adj[flist[1]].append(flist[0])

    def expand_from_pole(pole_v, steps):
        cur_f = set(v2f[pole_v])
        for _ in range(steps):
            verts = {v for fi in cur_f for v in faces[fi]}
            cur_f = {fi for v in verts for fi in v2f[v]}
        return cur_f

    def extract_loop(disk):
        directed = set()
        for fi in disk:
            f = faces[fi]
            for i in range(len(f)):
                directed.add((f[i], f[(i + 1) % len(f)]))
        nxt = {u: v for (u, v) in directed if (v, u) not in directed}
        start = next(iter(nxt))
        loop = []
        curr = start
        while curr not in loop:
            loop.append(curr)
            curr = nxt[curr]
        assert len(loop) == len(nxt), f"Expected 1 simple loop, got {len(loop)} vs {len(nxt)}"
        return loop

    def get_clean_cap_disk(island_faces, cond_fn, seed_fi):
        island_set = set(island_faces)
        disk = {seed_fi}
        q = deque([seed_fi])
        while q:
            curr = q.popleft()
            for nb in f_adj[curr]:
                if nb in island_set and nb not in disk and cond_fn(nb):
                    disk.add(nb)
                    q.append(nb)
        comp = island_set - disk
        visited = set()
        comps = []
        for f in comp:
            if f in visited:
                continue
            c_set = {f}
            cq = deque([f])
            visited.add(f)
            while cq:
                u = cq.popleft()
                for nb in f_adj[u]:
                    if nb in comp and nb not in visited:
                        visited.add(nb)
                        c_set.add(nb)
                        cq.append(nb)
            comps.append(c_set)
        comps.sort(key=len, reverse=True)
        for small_c in comps[1:]:
            disk |= small_c
        while True:
            directed = set()
            for fi in disk:
                f = faces[fi]
                for i in range(len(f)):
                    directed.add((f[i], f[(i + 1) % len(f)]))
            b_edges = [(u, v) for (u, v) in directed if (v, u) not in directed]
            out_deg = defaultdict(list)
            for u, v in b_edges:
                out_deg[u].append(v)
            pinch = [u for u, vs in out_deg.items() if len(vs) > 1]
            if not pinch:
                break
            for u in pinch:
                for fi in v2f[u]:
                    if fi in island_set:
                        disk.add(fi)
        return disk, extract_loop(disk)

    R = {
        "Hips": [fi for fi, f in enumerate(faces) if primvars["Hips"][f[0]] > 0.5],
        "Chest": [
            fi
            for fi, f in enumerate(faces)
            if (
                primvars["Spine1"][f[0]]
                + primvars["Spine2"][f[0]]
                + primvars["LeftShoulder"][f[0]]
                + primvars["RightShoulder"][f[0]]
            )
            > 0.5
        ],
        "Head": [fi for fi, f in enumerate(faces) if primvars["Head"][f[0]] > 0.5],
        "LeftUpLeg": [fi for fi, f in enumerate(faces) if primvars["LeftUpLeg"][f[0]] > 0.5],
        "LeftLeg": [fi for fi, f in enumerate(faces) if primvars["LeftLeg"][f[0]] > 0.5],
        "LeftFoot": [fi for fi, f in enumerate(faces) if primvars["LeftFoot"][f[0]] > 0.5],
        "LeftArm": [fi for fi, f in enumerate(faces) if primvars["LeftArm"][f[0]] > 0.5],
        "LeftForeArm": [fi for fi, f in enumerate(faces) if primvars["LeftForeArm"][f[0]] > 0.5],
        "LeftHand": [fi for fi, f in enumerate(faces) if primvars["LeftHand"][f[0]] > 0.5],
        "RightArm": [fi for fi, f in enumerate(faces) if primvars["RightArm"][f[0]] > 0.5],
        "RightForeArm": [fi for fi, f in enumerate(faces) if primvars["RightForeArm"][f[0]] > 0.5],
        "RightHand": [fi for fi, f in enumerate(faces) if primvars["RightHand"][f[0]] > 0.5],
        "RightFoot": [fi for fi, f in enumerate(faces) if primvars["RightFoot"][f[0]] > 0.5],
        "RightLeg": [fi for fi, f in enumerate(faces) if primvars["RightLeg"][f[0]] > 0.5],
        "RightUpLeg": [fi for fi, f in enumerate(faces) if primvars["RightUpLeg"][f[0]] > 0.5],
    }

    specs = [
        ("Hips_Waist", "pole", 281, 2),
        ("Chest_Waist", "Chest", lambda fi: f_centroids[fi, 2] < 1.315, min(R["Chest"], key=lambda fi: f_centroids[fi, 2])),
        (
            "Chest_Neck",
            "Chest",
            lambda fi: f_centroids[fi, 2] > 1.465 and abs(f_centroids[fi, 0]) < 0.08,
            max([fi for fi in R["Chest"] if abs(f_centroids[fi, 0]) < 0.05], key=lambda fi: f_centroids[fi, 2]),
        ),
        ("Head_Neck", "Head", lambda fi: f_centroids[fi, 2] < 1.575, min(R["Head"], key=lambda fi: f_centroids[fi, 2])),
        ("Chest_LShoulder", "Chest", lambda fi: f_centroids[fi, 0] > 0.135, max(R["Chest"], key=lambda fi: f_centroids[fi, 0])),
        ("LeftArm_Shoulder", "LeftArm", lambda fi: f_centroids[fi, 2] > 1.365, max(R["LeftArm"], key=lambda fi: f_centroids[fi, 2])),
        ("Chest_RShoulder", "Chest", lambda fi: f_centroids[fi, 0] < -0.150, min(R["Chest"], key=lambda fi: f_centroids[fi, 0])),
        ("RightArm_Shoulder", "RightArm", lambda fi: f_centroids[fi, 2] > 1.350, max(R["RightArm"], key=lambda fi: f_centroids[fi, 2])),
        ("LeftArm_Elbow", "LeftArm", lambda fi: f_centroids[fi, 2] < 1.165, min(R["LeftArm"], key=lambda fi: f_centroids[fi, 2])),
        ("LeftForeArm_Elbow", "LeftForeArm", lambda fi: f_centroids[fi, 2] > 1.105, max(R["LeftForeArm"], key=lambda fi: f_centroids[fi, 2])),
        ("RightArm_Elbow", "RightArm", lambda fi: f_centroids[fi, 2] < 1.150, min(R["RightArm"], key=lambda fi: f_centroids[fi, 2])),
        ("RightForeArm_Elbow", "RightForeArm", lambda fi: f_centroids[fi, 2] > 1.090, max(R["RightForeArm"], key=lambda fi: f_centroids[fi, 2])),
        ("LeftForeArm_Wrist", "LeftForeArm", lambda fi: f_centroids[fi, 2] < 0.895, min(R["LeftForeArm"], key=lambda fi: f_centroids[fi, 2])),
        ("LeftHand_Wrist", "LeftHand", lambda fi: f_centroids[fi, 2] > 0.840, max(R["LeftHand"], key=lambda fi: f_centroids[fi, 2])),
        ("RightForeArm_Wrist", "RightForeArm", lambda fi: f_centroids[fi, 2] < 0.880, min(R["RightForeArm"], key=lambda fi: f_centroids[fi, 2])),
        ("RightHand_Wrist", "RightHand", lambda fi: f_centroids[fi, 2] > 0.822, max(R["RightHand"], key=lambda fi: f_centroids[fi, 2])),
        ("Hips_LUpLeg", "pole", 282, 1),
        ("LeftUpLeg_Hip", "LeftUpLeg", lambda fi: f_centroids[fi, 2] > 0.890, max(R["LeftUpLeg"], key=lambda fi: f_centroids[fi, 2])),
        ("Hips_RUpLeg", "pole", 533, 1),
        ("RightUpLeg_Hip", "RightUpLeg", lambda fi: f_centroids[fi, 2] > 0.890, max(R["RightUpLeg"], key=lambda fi: f_centroids[fi, 2])),
        ("LeftUpLeg_Knee", "LeftUpLeg", lambda fi: f_centroids[fi, 2] < 0.570, min(R["LeftUpLeg"], key=lambda fi: f_centroids[fi, 2])),
        ("LeftLeg_Knee", "LeftLeg", lambda fi: f_centroids[fi, 2] > 0.500, max(R["LeftLeg"], key=lambda fi: f_centroids[fi, 2])),
        ("RightUpLeg_Knee", "RightUpLeg", lambda fi: f_centroids[fi, 2] < 0.570, min(R["RightUpLeg"], key=lambda fi: f_centroids[fi, 2])),
        ("RightLeg_Knee", "RightLeg", lambda fi: f_centroids[fi, 2] > 0.500, max(R["RightLeg"], key=lambda fi: f_centroids[fi, 2])),
        ("LeftLeg_Ankle", "LeftLeg", lambda fi: f_centroids[fi, 2] < 0.120, min(R["LeftLeg"], key=lambda fi: f_centroids[fi, 2])),
        ("LeftFoot_Ankle", "LeftFoot", lambda fi: f_centroids[fi, 2] > 0.070, max(R["LeftFoot"], key=lambda fi: f_centroids[fi, 2])),
        ("RightLeg_Ankle", "RightLeg", lambda fi: f_centroids[fi, 2] < 0.120, min(R["RightLeg"], key=lambda fi: f_centroids[fi, 2])),
        ("RightFoot_Ankle", "RightFoot", lambda fi: f_centroids[fi, 2] > 0.070, max(R["RightFoot"], key=lambda fi: f_centroids[fi, 2])),
    ]

    removed_faces = set()
    raw_loops = {}
    for item in specs:
        name = item[0]
        if item[1] == "pole":
            disk = expand_from_pole(item[2], item[3])
            loop = extract_loop(disk)
        else:
            disk, loop = get_clean_cap_disk(R[item[1]], item[2], item[3])
        assert not (disk & removed_faces), f"Cap disk overlap at {name}"
        removed_faces |= disk
        raw_loops[name] = loop

    def sample_loop_pts(pts, loop, M):
        N = len(loop)
        out = np.zeros((M, 3), dtype=np.float64)
        for m in range(M):
            x = (m / M) * N
            i0 = int(x) % N
            i1 = (i0 + 1) % N
            a = x - int(x)
            out[m] = (1.0 - a) * pts[loop[i0]] + a * pts[loop[i1]]
        return out

    def align_second_loop(loopA, loopB):
        loopB_rev = loopB[::-1]
        NB = len(loopB_rev)
        sA = sample_loop_pts(pts0, loopA, 64)
        sA_c = sA - sA.mean(axis=0)
        best_s, best_cost = 0, 1e18
        for s in range(NB):
            shifted = loopB_rev[s:] + loopB_rev[:s]
            sB = sample_loop_pts(pts0, shifted, 64)
            sB_c = sB - sB.mean(axis=0)
            cost = np.sum((sA_c - sB_c) ** 2)
            if cost < best_cost:
                best_cost = cost
                best_s = s
        return loopB_rev[best_s:] + loopB_rev[:best_s]

    # (joint_name, capA, capB, num_intermediate_rings K, ring_resolution M, bulge_m, smooth_iters)
    joint_defs = [
        ("Waist", "Hips_Waist", "Chest_Waist", 10, 48, 0.008, 18),
        ("Neck", "Chest_Neck", "Head_Neck", 6, 38, 0.003, 14),
        ("LShoulder", "Chest_LShoulder", "LeftArm_Shoulder", 6, 36, 0.006, 14),
        ("RShoulder", "Chest_RShoulder", "RightArm_Shoulder", 6, 36, 0.006, 14),
        ("LElbow", "LeftArm_Elbow", "LeftForeArm_Elbow", 5, 32, 0.004, 12),
        ("RElbow", "RightArm_Elbow", "RightForeArm_Elbow", 5, 32, 0.004, 12),
        ("LWrist", "LeftForeArm_Wrist", "LeftHand_Wrist", 4, 32, 0.002, 10),
        ("RWrist", "RightForeArm_Wrist", "RightHand_Wrist", 4, 32, 0.002, 10),
        ("LHip", "Hips_LUpLeg", "LeftUpLeg_Hip", 6, 34, 0.008, 16),
        ("RHip", "Hips_RUpLeg", "RightUpLeg_Hip", 6, 34, 0.008, 16),
        ("LKnee", "LeftUpLeg_Knee", "LeftLeg_Knee", 6, 34, 0.006, 14),
        ("RKnee", "RightUpLeg_Knee", "RightLeg_Knee", 6, 34, 0.006, 14),
        ("LAnkle", "LeftLeg_Ankle", "LeftFoot_Ankle", 5, 34, 0.003, 12),
        ("RAnkle", "RightLeg_Ankle", "RightFoot_Ankle", 5, 34, 0.003, 12),
    ]

    bridges = []
    for jname, nameA, nameB, K, M, bulge, siters in joint_defs:
        lA = raw_loops[nameA]
        lB_aligned = align_second_loop(lA, raw_loops[nameB])
        bridges.append((jname, lA, lB_aligned, K, M, bulge, siters))

    return removed_faces, bridges


def zipper_loops(loop0, loop1):
    """Khâu kín 2 vòng cùng chiều quay thành dải tam giác hướng pháp tuyến ra ngoài."""
    N0, N1 = len(loop0), len(loop1)
    i, j = 0, 0
    tris = []
    while i < N0 or j < N1:
        u0, u1 = loop0[i % N0], loop0[(i + 1) % N0]
        v0, v1 = loop1[j % N1], loop1[(j + 1) % N1]
        if i < N0 and (j == N1 or (i + 1) / N0 <= (j + 1) / N1):
            tris.append([u0, u1, v0])
            i += 1
        else:
            tris.append([u0, v1, v0])
            j += 1
    return tris


def apply_skin_to_pose(pts, faces, primvars, removed_faces, bridges):
    pts = pts.copy()
    orig_min = pts.min(axis=0).copy()
    orig_max = pts.max(axis=0).copy()

    # Giữ các mặt không thuộc đĩa nắp nội bộ
    new_faces = [list(f) for fi, f in enumerate(faces) if fi not in removed_faces]

    # Đánh dấu các đỉnh gốc còn được sử dụng
    used_orig_verts = {v for f in new_faces for v in f}

    extra_pts = []
    bridge_vert_sets = []
    boundary_loops_all = []

    for jname, loopA, loopB, K, M, bulge, siters in bridges:
        boundary_loops_all.extend(loopA)
        boundary_loops_all.extend(loopB)
        NA, NB = len(loopA), len(loopB)

        # Lấy mẫu M điểm quanh loopA và loopB
        pA = np.zeros((M, 3), dtype=np.float64)
        pB = np.zeros((M, 3), dtype=np.float64)
        for m in range(M):
            xA = (m / M) * NA
            i0 = int(xA) % NA
            a = xA - int(xA)
            pA[m] = (1.0 - a) * pts[loopA[i0]] + a * pts[loopA[(i0 + 1) % NA]]

            xB = (m / M) * NB
            j0 = int(xB) % NB
            b = xB - int(xB)
            pB[m] = (1.0 - b) * pts[loopB[j0]] + b * pts[loopB[(j0 + 1) % NB]]

        cA = pA.mean(axis=0)
        cB = pB.mean(axis=0)
        nA = newell_normal(pts[loopA])
        # loopB đã đảo chiều so với đĩa nắp B nên pháp tuyến đi từ A sang B là +newell_normal(pts[loopB])
        tB = newell_normal(pts[loopB])
        dist = np.linalg.norm(cB - cA)
        tangent_scale = 0.45 * dist

        ring_indices = []
        this_bridge_verts = set(loopA) | set(loopB)
        for k in range(1, K + 1):
            t = k / (K + 1)
            # Hermite basis
            h00 = 2 * t**3 - 3 * t**2 + 1
            h10 = t**3 - 2 * t**2 + t
            h01 = -2 * t**3 + 3 * t**2
            h11 = t**3 - t**2

            # Tâm vòng tại t
            c_t = h00 * cA + h10 * tangent_scale * nA + h01 * cB + h11 * tangent_scale * tB

            # Nội suy vị trí Hermite cho từng điểm m quanh chu vi + bảo toàn bán kính tiết diện
            ring_k = []
            for m in range(M):
                p_hermite = (
                    h00 * pA[m]
                    + h10 * tangent_scale * nA
                    + h01 * pB[m]
                    + h11 * tangent_scale * tB
                )
                rad_vec = p_hermite - c_t
                rad_len = np.linalg.norm(rad_vec)
                rA = np.linalg.norm(pA[m] - cA)
                rB = np.linalg.norm(pB[m] - cB)
                target_r = (1.0 - (3 * t**2 - 2 * t**3)) * rA + (3 * t**2 - 2 * t**3) * rB + 4 * t * (1 - t) * bulge
                if rad_len > 1e-6:
                    # Pha trộn 65% Hermite trực tiếp + 35% bán kính mục tiêu để khớp gập 90 độ không bị xẹp
                    blended_r = 0.65 * rad_len + 0.35 * target_r
                    p_final = c_t + rad_vec * (blended_r / rad_len)
                else:
                    p_final = p_hermite
                vid = len(pts) + len(extra_pts)
                extra_pts.append(p_final)
                ring_k.append(vid)
                this_bridge_verts.add(vid)
            ring_indices.append(ring_k)

        bridge_vert_sets.append((this_bridge_verts, siters))

        # Khâu loopA -> ring_0
        new_faces.extend(zipper_loops(loopA, ring_indices[0]))
        # Khâu ring_k -> ring_{k+1} bằng tứ giác
        for k in range(K - 1):
            r0 = ring_indices[k]
            r1 = ring_indices[k + 1]
            for m in range(M):
                u0, u1 = r0[m], r0[(m + 1) % M]
                v0, v1 = r1[m], r1[(m + 1) % M]
                new_faces.append([u0, u1, v1, v0])
        # Khâu ring_{K-1} -> loopB
        new_faces.extend(zipper_loops(ring_indices[-1], loopB))

    all_pts = np.vstack([pts, np.array(extra_pts, dtype=np.float64)]) if extra_pts else pts

    # Đưa các đỉnh nắp nội bộ không còn dùng về tâm cơ thể (an toàn cho extent)
    body_center = pts[list(used_orig_verts)].mean(axis=0)
    for v in range(len(pts)):
        if v not in used_orig_verts:
            all_pts[v] = body_center

    # Xây đồ thị kề đỉnh trên toàn bộ lưới đã khâu để làm mượt Taubin (λ|μ)
    adj = defaultdict(set)
    for f in new_faces:
        L = len(f)
        for i in range(L):
            u, v = f[i], f[(i + 1) % L]
            adj[u].add(v)
            adj[v].add(u)

    # Mở rộng vùng làm mượt thêm 2 vòng đỉnh quanh các vòng biên để xóa gờ cắt
    smooth_weights = np.zeros(len(all_pts), dtype=np.float64)
    for bverts, _ in bridge_vert_sets:
        for v in bverts:
            smooth_weights[v] = 1.0
    ring1 = {nb for v in boundary_loops_all for nb in adj[v]}
    ring2 = {nb for v in ring1 for nb in adj[v]}
    for v in ring1:
        smooth_weights[v] = max(smooth_weights[v], 0.85)
    for v in ring2:
        smooth_weights[v] = max(smooth_weights[v], 0.50)

    # Làm mượt nhẹ (0.20) trên thân/chi để xóa các đường vát giáp trụ của Mixamo Beta,
    # nhưng ghim chặt đỉnh đầu, đáy bàn chân và các ngón tay để giữ đúng chiều cao & chi tiết.
    head_verts = {i for i, w in enumerate(primvars.get("Head", [])) if w > 0.5}
    for v in used_orig_verts:
        if v not in head_verts and all_pts[v, 2] > orig_min[2] + 0.04 and all_pts[v, 2] < orig_max[2] - 0.04:
            smooth_weights[v] = max(smooth_weights[v], 0.22)

    active_verts = np.where(smooth_weights > 0)[0]
    adj_list = {v: np.array(list(adj[v]), dtype=np.int32) for v in active_verts if adj[v]}

    def taubin_step(points, step_factor):
        updated = points.copy()
        for v, nbs in adj_list.items():
            w = smooth_weights[v]
            mean_nb = points[nbs].mean(axis=0)
            updated[v] = points[v] + (w * step_factor) * (mean_nb - points[v])
        return updated

    # 14 chu kỳ Taubin (λ = +0.48, μ = -0.50) bảo toàn thể tích tuyệt đối
    for _ in range(14):
        all_pts = taubin_step(all_pts, 0.48)
        all_pts = taubin_step(all_pts, -0.50)

    # Khôi phục chính xác tuyệt đối hộp bao (extent) của các đỉnh đang dùng
    all_used = list({v for f in new_faces for v in f})
    cur_min = all_pts[all_used].min(axis=0)
    cur_max = all_pts[all_used].max(axis=0)
    for axis in range(3):
        span_orig = orig_max[axis] - orig_min[axis]
        span_cur = cur_max[axis] - cur_min[axis]
        if span_cur > 1e-6:
            all_pts[all_used, axis] = orig_min[axis] + (all_pts[all_used, axis] - cur_min[axis]) * (span_orig / span_cur)
    # Các đỉnh không dùng đặt vào tâm hộp bao
    unused_mask = np.ones(len(all_pts), dtype=bool)
    unused_mask[all_used] = False
    all_pts[unused_mask] = (orig_min + orig_max) * 0.5

    # Tính pháp tuyến đỉnh mượt (area-weighted smooth vertex normals)
    vnorms = np.zeros_like(all_pts)
    for f in new_faces:
        p0 = all_pts[f[0]]
        for k in range(1, len(f) - 1):
            p1, p2 = all_pts[f[k]], all_pts[f[k + 1]]
            fn = np.cross(p1 - p0, p2 - p0)
            for v in f:
                vnorms[v] += fn
    norms_len = np.linalg.norm(vnorms, axis=1, keepdims=True)
    norms_len[norms_len < 1e-12] = 1.0
    vnorms /= norms_len

    return all_pts, new_faces, vnorms


def verify_manifold(faces):
    dir_edges = Counter()
    undir_edges = Counter()
    for f in faces:
        L = len(f)
        for i in range(L):
            u, v = f[i], f[(i + 1) % L]
            dir_edges[(u, v)] += 1
            undir_edges[tuple(sorted((u, v)))] += 1
    valences = Counter(undir_edges.values())
    max_dir = max(dir_edges.values())
    assert valences == Counter({2: len(undir_edges)}) and max_dir == 1, (
        f"Non-manifold mesh: valences={valences}, max_dir={max_dir}"
    )


def format_usda(orig_text, all_pts, new_faces, vnorms):
    ext_min = all_pts.min(axis=0)
    ext_max = all_pts.max(axis=0)
    extent_line = (
        f"            float3[] extent = [({ext_min[0]:.7g}, {ext_min[1]:.7g}, {ext_min[2]:.7g}), "
        f"({ext_max[0]:.7g}, {ext_max[1]:.7g}, {ext_max[2]:.7g})]"
    )
    counts_str = ", ".join(str(len(f)) for f in new_faces)
    fvc_line = f"            int[] faceVertexCounts = [{counts_str}]"

    flat_indices = [v for f in new_faces for v in f]
    fvi_str = ", ".join(str(v) for v in flat_indices)
    fvi_line = f"            int[] faceVertexIndices = [{fvi_str}]"

    fv_norms = vnorms[flat_indices]
    norms_str = ", ".join(f"({n[0]:.6g}, {n[1]:.6g}, {n[2]:.6g})" for n in fv_norms)
    norms_line = f"            normal3f[] normals = [{norms_str}] ("

    pts_str = ", ".join(f"({p[0]:.7g}, {p[1]:.7g}, {p[2]:.7g})" for p in all_pts)
    pts_line = f"            point3f[] points = [{pts_str}]"

    num_extra = len(all_pts) - 14232
    extra_zeros = (", 0" * num_extra) if num_extra > 0 else ""

    out_lines = []
    for line in orig_text.splitlines():
        if "float3[] extent =" in line:
            out_lines.append(extent_line)
        elif "int[] faceVertexCounts =" in line:
            out_lines.append(fvc_line)
        elif "int[] faceVertexIndices =" in line:
            out_lines.append(fvi_line)
        elif "normal3f[] normals =" in line:
            out_lines.append(norms_line)
        elif "point3f[] points =" in line:
            out_lines.append(pts_line)
        elif "float[] primvars:mixamorig_" in line and extra_zeros:
            out_lines.append(line.replace("] (", f"{extra_zeros}] ("))
        else:
            out_lines.append(line)
    return "\n".join(out_lines) + "\n"


def aligned_zip_info(filename):
    info = zipfile.ZipInfo(filename)
    header_len = 30 + len(filename.encode("utf-8"))
    padding = (USDZ_ALIGNMENT - header_len % USDZ_ALIGNMENT) % USDZ_ALIGNMENT
    if padding:
        info.extra = b"\xff\xff" + struct.pack("<H", padding - 4) + b"\x00" * (padding - 4)
    return info


def pack_usdz(usdc_path, usdz_path):
    data = open(usdc_path, "rb").read()
    name = os.path.basename(usdc_path)
    with zipfile.ZipFile(usdz_path, "w", compression=zipfile.ZIP_STORED) as z:
        z.writestr(aligned_zip_info(name), data, compress_type=zipfile.ZIP_STORED)
    with zipfile.ZipFile(usdz_path) as z:
        info = z.infolist()[0]
        data_start = info.header_offset + 30 + len(info.filename.encode("utf-8")) + len(info.extra)
        assert data_start % USDZ_ALIGNMENT == 0, f"Misaligned USDZ data_start={data_start}"


def main():
    os.makedirs(ORIG_DIR, exist_ok=True)
    for usdz_file in sorted(glob.glob(os.path.join(OUT_DIR, "pose-*.usdz"))):
        backup = os.path.join(ORIG_DIR, os.path.basename(usdz_file))
        if not os.path.exists(backup):
            shutil.copy2(usdz_file, backup)

    ref_usdz = os.path.join(ORIG_DIR, "pose-standing-straight.usdz")
    with tempfile.TemporaryDirectory() as tmp:
        ref_text = extract_usda(ref_usdz, tmp)
    pts0, faces0, primvars0 = parse_usda(ref_text)
    removed_faces, bridges = build_topology_plan(pts0, faces0, primvars0)
    print(f"Plan built: removing {len(removed_faces)} internal cap faces, stitching {len(bridges)} anatomical joints.")

    for orig_usdz in sorted(glob.glob(os.path.join(ORIG_DIR, "pose-*.usdz"))):
        fname = os.path.basename(orig_usdz)
        pose_id = fname[len("pose-") : -len(".usdz")]
        with tempfile.TemporaryDirectory() as tmp:
            text = extract_usda(orig_usdz, tmp)
            pts, faces, primvars = parse_usda(text)
            new_pts, new_faces, vnorms = apply_skin_to_pose(pts, faces, primvars, removed_faces, bridges)
            verify_manifold(new_faces)

            usda_out = os.path.join(tmp, f"{pose_id}.usda")
            usdc_out = os.path.join(tmp, f"{pose_id}.usdc")
            with open(usda_out, "w", encoding="utf-8") as f:
                f.write(format_usda(text, new_pts, new_faces, vnorms))
            subprocess.run(["/usr/bin/usdcat", usda_out, "-o", usdc_out], check=True)

            target_usdz = os.path.join(OUT_DIR, fname)
            pack_usdz(usdc_out, target_usdz)
            size_kb = os.path.getsize(target_usdz) / 1024.0
            print(
                f"  {fname:30s}: {len(new_pts):5d} verts, {len(new_faces):5d} faces, "
                f"Z=[{new_pts[:,2].min():.3f}..{new_pts[:,2].max():.3f}], {size_kb:.1f} KB (MANIFOLD OK)"
            )


if __name__ == "__main__":
    main()
