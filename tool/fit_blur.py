"""Melatih penilai buram (_blurWeights di lib/analysis/photo_analyzer.dart).

Regresi logistik atas ukuran ketajaman, diuji silang per adegan supaya versi
tajam dan buram dari adegan yang sama tidak terpisah ke data latih dan uji.
Tanpa numpy, cukup Python 3.

1. Jalankan test/photo_dataset_eval_test.dart dengan EWS_DATA_UJI dan
   EWS_FITUR=1, lalu salin hasil.csv jadi hasil_sebelum.csv (pembanding).
2. python -I tool/fit_blur.py DATA_DIR FITUR,FITUR,... --export
   --misses mencetak foto yang masih salah.

Fitur yang dipakai sekarang:
s1_peakMax,s1_peakMin,s2_wholeMax,s2_wholeMin,s2_peakMax,s2_peakMin,s2_edge,
s4_wholeMax,s4_wholeMin,s4_peakMax,s4_peakMin

Bias di kode = bias hasil ekspor dikurangi cut.
"""
import csv
import math
import random
import sys

data_dir = sys.argv[1]
rows = list(csv.DictReader(open(f"{data_dir}/fitur.csv", encoding="utf-8")))
old = {r["file"]: r for r in csv.DictReader(open(f"{data_dir}/hasil_sebelum.csv", encoding="utf-8"))}
all_names = [k for k in rows[0] if k not in ("label", "file")]
names = sys.argv[2].split(",") if len(sys.argv) > 2 else all_names

X, y, scene, files = [], [], [], []
for r in rows:
    X.append([float(r[n]) for n in names])
    y.append(0 if r["label"] == "sharp" else 1)
    scene.append(int(r["file"].split("_")[0]))
    files.append((r["label"], r["file"]))

n_feat = len(names)


def standardize(train_idx):
    mean = [sum(X[i][k] for i in train_idx) / len(train_idx) for k in range(n_feat)]
    sd = [
        math.sqrt(sum((X[i][k] - mean[k]) ** 2 for i in train_idx) / len(train_idx)) or 1
        for k in range(n_feat)
    ]
    return mean, sd


def fit(train_idx, l2=0.05, steps=1500, lr=0.3):
    mean, sd = standardize(train_idx)
    Z = {i: [(X[i][k] - mean[k]) / sd[k] for k in range(n_feat)] for i in train_idx}
    w = [0.0] * n_feat
    b = 0.0
    m = len(train_idx)
    for _ in range(steps):
        gw = [0.0] * n_feat
        gb = 0.0
        for i in train_idx:
            z = b + sum(w[k] * Z[i][k] for k in range(n_feat))
            p = 1 / (1 + math.exp(-max(-30, min(30, z))))
            e = p - y[i]
            gb += e
            for k in range(n_feat):
                gw[k] += e * Z[i][k]
        b -= lr * gb / m
        for k in range(n_feat):
            w[k] -= lr * (gw[k] / m + l2 * w[k])
    return w, b, mean, sd


def score(model, i):
    w, b, mean, sd = model
    return b + sum(w[k] * (X[i][k] - mean[k]) / sd[k] for k in range(n_feat))


scenes = sorted(set(scene))
random.Random(7).shuffle(scenes)
folds = [set(scenes[f::5]) for f in range(5)]
cv = [0.0] * len(X)
for f in range(5):
    train = [i for i in range(len(X)) if scene[i] not in folds[f]]
    test = [i for i in range(len(X)) if scene[i] in folds[f]]
    model = fit(train)
    for i in test:
        cv[i] = score(model, i)


def report(scores, cut, label):
    fp = sum(1 for i in range(len(X)) if y[i] == 0 and scores[i] >= cut)
    sharp = sum(1 for v in y if v == 0)
    out = {}
    for lab in ("defocused_blurred", "motion_blurred"):
        idx = [i for i in range(len(X)) if files[i][0] == lab]
        out[lab] = sum(1 for i in idx if scores[i] >= cut) / len(idx)
    print(
        f"{label}: tajam salah buram {fp}/{sharp} ({100*fp/sharp:.1f}%), "
        f"tidak fokus tertangkap {100*out['defocused_blurred']:.1f}%, "
        f"goyang tertangkap {100*out['motion_blurred']:.1f}%"
    )


# Baseline: aturan lama (Buram, tanpa Agak buram), hanya untuk perbandingan.
base = [1.0 if "Buram" in old[f]["issues"].replace("Agak buram", "") else 0.0 for _, f in files]
report(base, 0.5, "aturan lama        ")
for target in (0.02, 0.03, 0.05):
    sharp_scores = sorted(cv[i] for i in range(len(X)) if y[i] == 0)
    cut = sharp_scores[int((1 - target) * (len(sharp_scores) - 1))]
    report(cv, cut, f"model, salah <={int(target*100)}%   ")

final = fit(list(range(len(X))))
w, b, mean, sd = final
print("\nbobot (terstandar), terbesar dulu:")
for k in sorted(range(n_feat), key=lambda k: -abs(w[k]))[:12]:
    print(f"  {names[k]:12s} {w[k]:+.3f}  (rata {mean[k]:.4f}, sd {sd[k]:.4f})")

if "--misses" in sys.argv:
    sharp_scores = sorted(cv[i] for i in range(len(X)) if y[i] == 0)
    cut = sharp_scores[int(0.97 * (len(sharp_scores) - 1))]
    print("\nmasih lolos (goyang/tidak fokus), skor terendah dulu:")
    miss = sorted((cv[i], files[i]) for i in range(len(X)) if y[i] == 1 and cv[i] < cut)
    for s, (lab, f) in miss[:40]:
        print(f"  {s:+.2f} {lab[:6]} {f}")
    print("\ntajam salah buram:")
    for i in range(len(X)):
        if y[i] == 0 and cv[i] >= cut:
            print(f"  {cv[i]:+.2f} {files[i][1]}")

if "--export" in sys.argv:
    w, b, mean, sd = final
    raw = [w[k] / sd[k] for k in range(n_feat)]
    bias = b - sum(w[k] * mean[k] / sd[k] for k in range(n_feat))
    full = [bias + sum(raw[k] * X[i][k] for k in range(n_feat)) for i in range(len(X))]
    sharp_full = sorted(full[i] for i in range(len(X)) if y[i] == 0)
    cut = sharp_full[int(0.97 * (len(sharp_full) - 1))]
    print("\nbias", round(bias, 4), "cut", round(cut, 4))
    for k in range(n_feat):
        print(f"  ('{names[k]}', {raw[k]:.4f}),")
    report(full, cut, "model akhir (di data latih)")
