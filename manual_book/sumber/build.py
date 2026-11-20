"""Membuat ../Manual_Book_EWS_Lumeneng.pdf dari manual.html.

    python manual_book/sumber/build.py

Butuh Microsoft Edge atau Google Chrome, dan pypdf (pip install pypdf).
Edge mencetak HTML ke PDF; skrip ini lalu menambah bookmark dan judul dokumen.
"""

import logging
import re
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

from pypdf import PdfReader, PdfWriter

# PDF dari Edge memicu peringatan ukuran trailer yang tidak berpengaruh.
logging.getLogger("pypdf").setLevel(logging.ERROR)

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "Manual_Book_EWS_Lumeneng.pdf"

BROWSERS = [
    Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
    Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
]

# Judul bookmark dan teks yang pertama kali muncul di halaman awal bagian itu.
# Dicari berurutan, jadi judul bab di Daftar Isi tidak ikut terhitung.
OUTLINE = [
    ("Identitas Buku", "IDENTITAS BUKU"),
    ("Kata Pengantar", "KATA PENGANTAR"),
    ("Daftar Isi", "DAFTAR ISI"),
    ("Tujuan Buku Panduan", "TUJUAN BUKU PANDUAN"),
    ("Bab 1  Mengenal EWS Lumeneng", "Mengenal EWS Lumeneng"),
    ("Bab 2  Memasang dan Membuka Aplikasi", "Memasang dan Membuka Aplikasi"),
    ("Bab 3  Mengenal Tampilan", "Mengenal Tampilan"),
    ("Bab 4  Menu Beranda", "Menu Beranda"),
    ("Bab 5  Menu Sensor", "Menu Sensor"),
    ("Bab 6  Menu Lapor", "Menu Lapor: Melaporkan Tanda Longsor"),
    ("Bab 7  Notifikasi dan Peringatan", "Notifikasi dan Peringatan"),
    ("Bab 8  Sinyal Lemah dan Alat Tidak Mengirim Data",
     "Saat Sinyal Lemah atau Alat Tidak Mengirim Data"),
    ("Bab 9  Tentang Aplikasi, Data, dan Privasi", "Tentang Aplikasi, Data, dan Privasi"),
    ("Bab 10  Pemecahan Masalah", "Pemecahan Masalah"),
    ("Lampiran: Kartu Siaga", "Kartu Siaga"),
    ("Glosarium", "GLOSARIUM"),
    ("Penutup", "PENUTUP"),
]


def print_html(html: Path, pdf: Path, profile: Path) -> None:
    browser = next((b for b in BROWSERS if b.exists()), None)
    if browser is None:
        sys.exit("Edge atau Chrome tidak ditemukan.")
    subprocess.run(
        [
            str(browser),
            "--headless=new",
            "--disable-gpu",
            "--no-pdf-header-footer",
            f"--user-data-dir={profile}",
            # Waktu untuk memuat font, gambar, dan nomor halaman dari skrip.
            "--virtual-time-budget=20000",
            f"--print-to-pdf={pdf}",
            html.as_uri(),
        ],
        check=True,
        capture_output=True,
    )


def squash(text: str) -> str:
    # NFKC mengubah ligatur "ﬁ" (mis. di "Notifikasi") kembali menjadi "fi".
    return re.sub(r"\s+", "", unicodedata.normalize("NFKC", text))


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "manual.pdf"
        print_html(HERE / "manual.html", raw, Path(tmp) / "profil")

        reader = PdfReader(raw)
        texts = [squash(page.extract_text() or "") for page in reader.pages]
        writer = PdfWriter(clone_from=reader)

        start = 0
        for title, needle in OUTLINE:
            target = squash(needle)
            page = next((i for i in range(start, len(texts)) if target in texts[i]), None)
            if page is None:
                sys.exit(f"Halaman untuk bookmark '{title}' tidak ditemukan.")
            writer.add_outline_item(title, page)
            start = page

        writer.add_metadata({
            "/Title": "Manual Book Aplikasi EWS Lumeneng",
            "/Author": "Tim Aksara Desa Lumeneng 2026",
            "/Subject": "Panduan memakai aplikasi peringatan dini tanah longsor "
                        "untuk warga Desa Lumeneng",
            "/Keywords": "EWS, Lumeneng, longsor, peringatan dini, manual book",
        })
        writer.page_mode = "/UseOutlines"
        with OUT.open("wb") as f:
            writer.write(f)

    print(f"{OUT} ({len(texts)} halaman)")


if __name__ == "__main__":
    main()
