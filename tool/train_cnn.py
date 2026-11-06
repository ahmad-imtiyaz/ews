"""Latih CNN klasifikasi foto laporan longsor lalu ekspor ke TFLite.

MobileNetV2 (bobot ImageNet) dipakai sebagai ekstraktor fitur dan hanya
kepala klasifikasinya yang dilatih, karena jumlah foto lokal masih sedikit.

Susunan data (label folder harus sama dengan SignCategory.code):

    dataset/
      train/
        longsoran/  pohon_miring/  rembesan/  retakan/  tidak_relevan/
      val/
        longsoran/  pohon_miring/  rembesan/  retakan/  tidak_relevan/

Pisahkan train dan val per kejadian, bukan per foto. Foto dari kejadian yang
sama atau hasil augmentasinya tidak boleh ada di kedua folder.

Pakai:
    pip install tensorflow==2.17.*
    python tool/train_cnn.py --data dataset --epochs 15

Hasil: assets/models/cnn_longsor.tflite dan assets/models/labels.txt.
Aplikasi memberi input 224 x 224 x 3 dengan nilai 0-1.
"""

import argparse
import pathlib

import numpy as np
import tensorflow as tf

IMAGE_SIZE = 224
ROOT = pathlib.Path(__file__).resolve().parent.parent
MODELS = ROOT / "assets" / "models"


def load_split(path, shuffle):
    return tf.keras.utils.image_dataset_from_directory(
        path,
        image_size=(IMAGE_SIZE, IMAGE_SIZE),
        batch_size=16,
        shuffle=shuffle,
        label_mode="int",
    )


def build_model(class_count):
    base = tf.keras.applications.MobileNetV2(
        input_shape=(IMAGE_SIZE, IMAGE_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
    base.trainable = False

    inputs = tf.keras.Input((IMAGE_SIZE, IMAGE_SIZE, 3))
    # Input 0-1 dari aplikasi diubah ke -1..1 sesuai MobileNetV2.
    x = tf.keras.layers.Rescaling(2.0, offset=-1.0)(inputs)
    x = base(x, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    outputs = tf.keras.layers.Dense(class_count, activation="softmax")(x)
    return tf.keras.Model(inputs, outputs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default="dataset")
    parser.add_argument("--epochs", type=int, default=15)
    args = parser.parse_args()

    data = pathlib.Path(args.data)
    train = load_split(data / "train", shuffle=True)
    val = load_split(data / "val", shuffle=False)
    class_names = train.class_names
    if val.class_names != class_names:
        raise SystemExit("Folder kelas train dan val tidak sama.")

    augment = tf.keras.Sequential(
        [
            tf.keras.layers.RandomFlip("horizontal"),
            tf.keras.layers.RandomRotation(0.08),
            tf.keras.layers.RandomBrightness(0.2, value_range=(0, 1)),
            tf.keras.layers.RandomZoom(0.15),
        ]
    )
    scale = tf.keras.layers.Rescaling(1 / 255)
    train = train.map(lambda x, y: (augment(scale(x), training=True), y))
    val = val.map(lambda x, y: (scale(x), y))

    model = build_model(len(class_names))
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.fit(train, validation_data=val, epochs=args.epochs)

    labels = np.concatenate([y.numpy() for _, y in val])
    predicted = np.argmax(model.predict(val), axis=1)
    matrix = tf.math.confusion_matrix(labels, predicted, len(class_names))
    print("\nConfusion matrix (baris = label, kolom = tebakan):")
    print("  ".join(class_names))
    print(matrix.numpy())
    for index, name in enumerate(class_names):
        tp = int(matrix[index, index])
        precision = tp / max(int(tf.reduce_sum(matrix[:, index])), 1)
        recall = tp / max(int(tf.reduce_sum(matrix[index, :])), 1)
        f1 = 2 * precision * recall / max(precision + recall, 1e-9)
        print(f"{name:14} presisi {precision:.2f}  recall {recall:.2f}  F1 {f1:.2f}")

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    MODELS.mkdir(parents=True, exist_ok=True)
    (MODELS / "cnn_longsor.tflite").write_bytes(converter.convert())
    (MODELS / "labels.txt").write_text("\n".join(class_names) + "\n")
    print(f"\nModel tersimpan di {MODELS / 'cnn_longsor.tflite'}")


if __name__ == "__main__":
    main()
