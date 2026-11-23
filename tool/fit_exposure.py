"""Melatih penilai pencahayaan (_exposureWeights di lib/analysis/photo_analyzer.dart).

Data: SPAQ (Fang dkk., CVPR 2020; hanya untuk pendidikan dan riset). Nilai
Brightness di sana adalah mutu pencahayaan menurut penilai manusia: rendah
untuk foto yang terlalu gelap maupun terlalu terang. Label: di bawah 30 buruk,
40 ke atas baik, di antaranya tidak dipakai.

1. Taruh foto SPAQ di DATA_DIR/foto, nilai di DATA_DIR/nilai.csv (kolom
   "Image name" dan "Brightness" dari "MOS and Image attribute scores.xlsx").
2. Jalankan test/photo_dataset_eval_test.dart dengan EWS_DATA_UJI=DATA_DIR,
   EWS_FITUR=1, EWS_SEPERTI_APLIKASI=1.
3. python -I tool/fit_exposure.py DATA_DIR gelap|terang FITUR,... [--export]

Gelap dan terang dilatih terpisah: foto buruk dengan kecerahan rata-rata di
bawah 128 untuk "gelap", sisanya untuk "terang". Foto baik dipakai di
keduanya.
"""
import csv
import math
import random
import sys

data_dir = sys.argv[1]
score = {
    r["Image name"]: float(r["Brightness"])
    for r in csv.DictReader(open(f"{data_dir}/nilai.csv", encoding="utf-8"))
}
old = {r["file"]: r["issues"] for r in csv.DictReader(open(f"{data_dir}/hasil.csv", encoding="utf-8"))}
side = sys.argv[2]
names = sys.argv[3].split(",")

X, y, files = [], [], []
for r in csv.DictReader(open(f"{data_dir}/fitur.csv", encoding="utf-8")):
    s = score[r["file"]]
    if 30 <= s < 40:
        continue
    if s < 30 and (float(r["e_mean"]) < 128) != (side == "gelap"):
        continue
    X.append([float(r[n]) for n in names])
    y.append(1 if s < 30 else 0)
    files.append(r["file"])
n_feat = len(names)


def fit(idx, l2=0.05, steps=2000, lr=0.3):
    mean = [sum(X[i][k] for i in idx) / len(idx) for k in range(n_feat)]
    sd = [math.sqrt(sum((X[i][k] - mean[k]) ** 2 for i in idx) / len(idx)) or 1 for k in range(n_feat)]
    Z = {i: [(X[i][k] - mean[k]) / sd[k] for k in range(n_feat)] for i in idx}
    w, b = [0.0] * n_feat, 0.0
    for _ in range(steps):
        gw, gb = [0.0] * n_feat, 0.0
        for i in idx:
            z = b + sum(w[k] * Z[i][k] for k in range(n_feat))
            e = 1 / (1 + math.exp(-max(-30, min(30, z)))) - y[i]
            gb += e
            for k in range(n_feat):
                gw[k] += e * Z[i][k]
        b -= lr * gb / len(idx)
        for k in range(n_feat):
            w[k] -= lr * (gw[k] / len(idx) + l2 * w[k])
    return w, b, mean, sd


def score_of(model, i):
    w, b, mean, sd = model
    return b + sum(w[k] * (X[i][k] - mean[k]) / sd[k] for k in range(n_feat))


order = list(range(len(X)))
random.Random(7).shuffle(order)
folds = [set(order[f::5]) for f in range(5)]
cv = [0.0] * len(X)
for f in range(5):
    model = fit([i for i in range(len(X)) if i not in folds[f]])
    for i in folds[f]:
        cv[i] = score_of(model, i)

good = [i for i in range(len(X)) if y[i] == 0]
bad = [i for i in range(len(X)) if y[i] == 1]


def report(flag, label):
    fp = sum(1 for i in good if flag(i))
    tp = sum(1 for i in bad if flag(i))
    print(f"{label}: foto baik diberi peringatan {fp}/{len(good)} ({100*fp/len(good):.1f}%), "
          f"foto buruk tertangkap {tp}/{len(bad)} ({100*tp/len(bad):.1f}%)")


word = "gelap" if side == "gelap" else "terang"
report(lambda i: word in old[files[i]], "aturan lama          ")
for target in (0.02, 0.03, 0.05):
    cut = sorted(cv[i] for i in good)[int((1 - target) * (len(good) - 1))]
    report(lambda i, c=cut: cv[i] >= c, f"model, salah <={int(target*100)}%   ")

if "--export" in sys.argv:
    w, b, mean, sd = fit(list(range(len(X))))
    raw = [w[k] / sd[k] for k in range(n_feat)]
    bias = b - sum(w[k] * mean[k] / sd[k] for k in range(n_feat))
    full = [bias + sum(raw[k] * X[i][k] for k in range(n_feat)) for i in range(len(X))]
    # Foto baik yang diberi peringatan paling banyak 2%.
    cut = sorted(full[i] for i in good)[int(0.98 * (len(good) - 1))]
    print(f"\nbias {bias:.4f} cut {cut:.4f} (bias di kode = bias - cut)")
    for k in range(n_feat):
        print(f"  '{names[k]}': {raw[k]:.5f},")
    report(lambda i: full[i] >= cut, "model akhir (data latih)")
