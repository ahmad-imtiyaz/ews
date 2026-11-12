const path = require("path");
const React = require("react");
const ReactDOMServer = require("react-dom/server");
const sharp = require("sharp");
const pptxgen = require("pptxgenjs");
const fa = require("react-icons/fa");
const { applyTheme } = require(process.argv[2]);

const OUT = process.argv[3];
const IMG = path.join(__dirname, "img");
const BRAND = process.argv[4];
const img = (name) => path.join(IMG, name);

const THEME = {
  name: "EWS Lumeneng",
  headFontFace: "Arial",
  bodyFontFace: "Arial",
  colors: {
    dk1: "0D121E",
    lt1: "FFFFFF",
    dk2: "1C2842",
    lt2: "C3CCDB",
    accent1: "08BDF0",
    accent2: "0A6FD0",
    accent3: "3DBE6E",
    accent4: "F2B60C",
    accent5: "E5534B",
    accent6: "8A94A6",
    hlink: "08BDF0",
    folHlink: "7FD8F5",
  },
};

const W = 13.333;
const PHONE_RATIO = 626 / 1352;
const LEFT = 0.95;

async function icon(Component, color = "#FFFFFF") {
  const svg = ReactDOMServer.renderToStaticMarkup(
    React.createElement(Component, { color, size: 256 })
  );
  const buf = await sharp(Buffer.from(svg)).resize(256, 256).png().toBuffer();
  return "image/png;base64," + buf.toString("base64");
}

(async () => {
  const pres = new pptxgen();
  pres.layout = "LAYOUT_WIDE";
  pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
  pres.title = "EWS Lumeneng";
  pres.subject = "Pengenalan aplikasi peringatan dini tanah longsor Desa Lumeneng";
  const C = pres.SchemeColor;
  const WHITE = C.background1;
  const MUTED = C.background2;
  const CARD = C.text2;
  const CYAN = C.accent1;
  const BLUE = C.accent2;

  const titleOptions = (x, w) => ({
    name: "title", type: "title", x, y: 0.98, w, h: 0.9,
    fontSize: 36, bold: true, color: WHITE, align: "left", valign: "middle", margin: 0,
  });
  const pageNumber = { x: 12.15, y: 6.72, w: 0.6, h: 0.3, fontSize: 10, color: MUTED, align: "right" };

  pres.defineSlideMaster({
    title: "Sampul",
    background: { path: img("bg_cover.png") },
    objects: [
      { placeholder: { options: { name: "title", type: "title", x: LEFT, y: 3.25, w: 6.2, h: 1.5, fontSize: 36, bold: true, color: WHITE, align: "left", valign: "top", margin: 0 }, text: "" } },
      { placeholder: { options: { name: "body", type: "body", x: LEFT, y: 4.95, w: 6.0, h: 0.9, fontSize: 16, color: WHITE, align: "left", valign: "top", margin: 0 }, text: "" } },
    ],
  });
  pres.defineSlideMaster({
    title: "Judul kiri",
    background: { path: img("bg_panel.png") },
    objects: [{ placeholder: { options: titleOptions(LEFT, 8.6), text: "" } }],
    slideNumber: pageNumber,
  });
  pres.defineSlideMaster({
    title: "Judul lebar",
    background: { path: img("bg_panel_soft.png") },
    objects: [{ placeholder: { options: titleOptions(LEFT, 11.4), text: "" } }],
    slideNumber: { ...pageNumber },
  });
  pres.defineSlideMaster({
    title: "Judul kanan",
    background: { path: img("bg_panel.png") },
    objects: [{ placeholder: { options: titleOptions(6.55, 6.1), text: "" } }],
    slideNumber: { ...pageNumber },
  });

  const icons = {
    mountain: await icon(fa.FaMountain),
    tower: await icon(fa.FaBroadcastTower),
    signal: await icon(fa.FaWifi),
    bolt: await icon(fa.FaMobileAlt),
    users: await icon(fa.FaUsers),
    server: await icon(fa.FaServer),
    map: await icon(fa.FaMapMarkedAlt),
    bell: await icon(fa.FaBell),
    tint: await icon(fa.FaTint),
    rain: await icon(fa.FaCloudRain),
    slope: await icon(fa.FaChartLine),
    wind: await icon(fa.FaWind),
    check: await icon(fa.FaCheck),
    clock: await icon(fa.FaHourglassHalf),
    shield: await icon(fa.FaShieldAlt),
    warn: await icon(fa.FaExclamation, "#111111"),
    cross: await icon(fa.FaTimes),
    question: await icon(fa.FaQuestion),
    arrow: await icon(fa.FaArrowRight, "#08BDF0"),
  };

  // --- potongan yang dipakai berulang ---
  const text = (slide, value, o) =>
    slide.addText(value, { isTextBox: true, margin: 0, valign: "top", align: "left", ...o });

  const kicker = (slide, value, x = LEFT) =>
    text(slide, value.toUpperCase(), {
      x, y: 0.66, w: 6, h: 0.3, fontSize: 12, bold: true, color: CYAN, charSpacing: 2,
      objectName: "Label bagian",
    });

  const phone = (slide, name, x, y, h, extra = {}) =>
    slide.addImage({
      path: img(`phone_${name}.png`), x, y, w: h * PHONE_RATIO, h,
      altText: extra.altText, objectName: extra.objectName || `HP ${name}`, rotate: extra.rotate,
    });

  const tile = (slide, x, y, size, data, color = BLUE, name = "Ikon") => {
    slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
      x, y, w: size, h: size, rectRadius: 0.12, fill: { color }, line: { color, width: 0 },
      objectName: `${name} latar`,
    });
    const pad = size * 0.27;
    slide.addImage({ data, x: x + pad, y: y + pad, w: size - pad * 2, h: size - pad * 2, objectName: name });
  };

  const numberTile = (slide, x, y, label) =>
    slide.addText(label, {
      shape: pres.shapes.ROUNDED_RECTANGLE, rectRadius: 0.1, isTextBox: true,
      x, y, w: 0.62, h: 0.62, fill: { color: BLUE }, line: { color: BLUE, width: 0 },
      fontSize: 16, bold: true, color: WHITE, align: "center", valign: "middle", margin: 0,
      objectName: `Nomor ${label}`,
    });

  const card = (slide, x, y, w, h, name) =>
    slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
      x, y, w, h, rectRadius: 0.18, fill: { color: CARD }, line: { color: CARD, width: 0 },
      objectName: name,
    });

  const headed = (slide, x, y, w, head, body, bodyH = 0.8) => {
    text(slide, head, { x, y, w, h: 0.36, fontSize: 18, bold: true, color: WHITE, objectName: `Judul: ${head}` });
    text(slide, body, { x, y: y + 0.42, w, h: bodyH, fontSize: 14, color: MUTED, objectName: `Isi: ${head}` });
  };

  // ============ 1. Sampul ============
  pres.addSection({ title: "Pembuka" });
  {
    const s = pres.addSlide({ masterName: "Sampul", sectionTitle: "Pembuka" });
    s.addImage({
      path: path.join(BRAND, "logo_wordmark_light.png"), x: LEFT, y: 1.35, w: 4.8, h: 4.8 * (228 / 686),
      altText: "Logo EWS Lumeneng", objectName: "Logo",
    });
    s.addText("Aplikasi peringatan dini tanah longsor", { placeholder: "title" });
    s.addText("Untuk warga Desa Lumeneng, Kecamatan Paninggaran, Kabupaten Pekalongan", { placeholder: "body" });
    phone(s, "splash", 7.15, 1.25, 5.0, { rotate: -7, altText: "Layar pembuka aplikasi" });
    phone(s, "beranda", 10.15, 1.0, 5.0, { rotate: 7, altText: "Layar Beranda aplikasi" });
    s.addNotes(
      "Perkenalkan diri dan tim. Sampaikan bahwa hari ini kita mengenal aplikasi EWS Lumeneng: apa itu, kenapa dibuat, apa saja menunya, dan sejauh mana aplikasinya sudah berjalan."
    );
  }

  // ============ 2. Arti logo ============
  pres.addSection({ title: "Tentang aplikasi" });
  {
    const s = pres.addSlide({ masterName: "Judul kiri", sectionTitle: "Tentang aplikasi" });
    kicker(s, "Logo");
    s.addText("Arti logo EWS Lumeneng", { placeholder: "title" });
    s.addImage({ path: img("logo_card.png"), x: LEFT, y: 2.3, w: 3.9, h: 3.9, altText: "Simbol logo EWS Lumeneng", objectName: "Simbol logo" });
    const x = 5.6;
    const rows = [
      [icons.mountain, "Bukit dan lereng", "Desa Lumeneng yang berbukit, tempat yang dijaga."],
      [icons.tower, "Tiang alat EWS", "Alat di lereng yang terus membaca kondisi tanah."],
      [icons.signal, "Gelombang sinyal", "Tanda peringatan yang dikirim ke HP warga."],
    ];
    rows.forEach(([data, head, body], i) => {
      const y = 2.3 + i * 1.12;
      tile(s, x, y, 0.78, data, BLUE, `Ikon ${head}`);
      headed(s, x + 1.05, y, 5.8, head, body, 0.4);
    });
    card(s, x, 5.72, 6.85, 0.92, "Kartu pesan logo");
    text(s, "Alat yang menjaga lereng desa dan memberi tanda lebih dulu sebelum longsor.", {
      x: x + 0.3, y: 5.72, w: 6.25, h: 0.92, fontSize: 16, italic: true, color: WHITE, valign: "middle",
      objectName: "Pesan logo",
    });
    s.addNotes(
      "Logo menggabungkan dua hal: lereng desa yang dijaga, dan alat yang terus memantau lalu mengirim tanda. Warna biru dipilih supaya terasa tenang, tidak seperti warna peringatan."
    );
  }

  // ============ 3. Apa itu ============
  {
    const s = pres.addSlide({ masterName: "Judul kiri", sectionTitle: "Tentang aplikasi" });
    kicker(s, "Tentang aplikasi");
    s.addText("Apa itu EWS Lumeneng?", { placeholder: "title" });
    text(s, [
      { text: "EWS singkatan dari Early Warning System, artinya sistem peringatan dini.", options: { breakLine: true, bold: true, color: WHITE } },
      { text: "Aplikasi ini menunjukkan kondisi lereng desa dari alat yang dipasang di lapangan, dan memberi tahu warga lebih dulu saat ada tanda bahaya longsor.", options: {} },
    ], { x: LEFT, y: 2.2, w: 7.6, h: 1.9, fontSize: 16, color: MUTED, paraSpaceAfter: 10, objectName: "Penjelasan" });
    const cards = [
      [icons.bolt, "Langsung dipakai", "Buka aplikasi, peta langsung tampil. Tidak perlu daftar atau login."],
      [icons.users, "Untuk semua warga", "Dibuat untuk warga desa, termasuk orang tua, dan perangkat desa."],
    ];
    cards.forEach(([data, head, body], i) => {
      const x = LEFT + i * 3.95;
      card(s, x, 4.45, 3.7, 2.05, `Kartu ${head}`);
      tile(s, x + 0.3, 4.72, 0.62, data, BLUE, `Ikon ${head}`);
      text(s, head, { x: x + 1.1, y: 4.72, w: 2.4, h: 0.62, fontSize: 18, bold: true, color: WHITE, valign: "middle", objectName: `Judul: ${head}` });
      text(s, body, { x: x + 0.3, y: 5.5, w: 3.1, h: 0.85, fontSize: 14, color: MUTED, objectName: `Isi: ${head}` });
    });
    phone(s, "beranda", 9.55, 0.95, 5.6, { altText: "Layar Beranda: peta desa dan catatan terbaru" });
    s.addNotes(
      "Tekankan kata 'lebih dulu'. Aplikasi tidak mencegah longsor, tetapi memberi waktu bagi warga untuk bersiap. Tunjukkan bahwa saat dibuka, aplikasi langsung masuk ke peta tanpa perlu membuat akun."
    );
  }

  // ============ 4. Sejarah singkat ============
  {
    const s = pres.addSlide({ masterName: "Judul lebar", sectionTitle: "Tentang aplikasi" });
    kicker(s, "Sejarah singkat");
    s.addText("Dari longsor 1944 sampai alat EWS", { placeholder: "title" });
    const items = [
      ["1944", "Longsor Gunung Bongkok", "Hampir seluruh Dukuh Sikudi tergusur. Dari sekitar 40 KK, tersisa 4 rumah. Banyak warga selamat karena mengenali tandanya, lalu mendirikan Dukuh Sumingkir."],
      ["2008–2024", "Sepuluh longsor lagi", "Paling sering di Kaliwisnu, Wanasida, dan Sikembang. Rumah, jalan, sawah, dan jaringan air rusak."],
      ["2024", "Kajian pemetaan bencana", "LPBI NU Kabupaten Pekalongan dan Ringan Tangan Indonesia memetakan daerah rawan longsor di desa."],
      ["2026", "Alat EWS dan aplikasi", "Tim KKN memasang alat EWS di lereng dan membuat aplikasi ini. EWS-02 di Sikembang lebih dulu, EWS-01 di Jomparang menyusul."],
    ];
    const colW = 2.72, gap = 0.26, top = 2.12;
    s.addShape(pres.shapes.LINE, {
      x: LEFT + 0.11, y: top + 0.11, w: 3 * (colW + gap), h: 0,
      line: { color: C.accent6, width: 1.5 }, objectName: "Garis waktu",
    });
    items.forEach(([year, head, body], i) => {
      const x = LEFT + i * (colW + gap);
      s.addShape(pres.shapes.OVAL, { x, y: top, w: 0.22, h: 0.22, fill: { color: CYAN }, line: { color: CYAN, width: 0 }, objectName: `Titik ${year}` });
      text(s, year, { x, y: top + 0.42, w: colW, h: 0.55, fontSize: 28, bold: true, color: CYAN, objectName: `Tahun ${year}` });
      text(s, head, { x, y: top + 1.08, w: colW, h: 0.62, fontSize: 16, bold: true, color: WHITE, objectName: `Judul ${year}` });
      text(s, body, { x, y: top + 1.74, w: colW, h: 1.9, fontSize: 14, color: MUTED, objectName: `Isi ${year}` });
    });
    card(s, LEFT, 5.55, 11.43, 0.74, "Kartu pelajaran 1944");
    text(s, "Pelajaran dari 1944: tanda yang dikenali lebih dulu menyelamatkan warga.", {
      x: LEFT + 0.3, y: 5.55, w: 10.8, h: 0.74, fontSize: 16, italic: true, color: WHITE, valign: "middle",
      objectName: "Pelajaran 1944",
    });
    text(s, "Sumber: Kajian Pemetaan Bencana Desa Lumeneng 2024.", {
      x: LEFT, y: 6.5, w: 8, h: 0.28, fontSize: 11, color: MUTED, objectName: "Sumber",
    });
    s.addNotes(
      "Cerita 1944 adalah inti slide ini: warga Sikudi selamat karena mengenali tanda longsor lebih dulu, lalu pindah dan mendirikan Dukuh Sumingkir, yang artinya menyingkir dari bahaya. Aplikasi ini melanjutkan hal yang sama dengan bantuan alat. Dari 1944 sampai 2024 tercatat 11 kejadian longsor."
    );
  }

  // ============ 5. Cara kerja ============
  {
    const s = pres.addSlide({ masterName: "Judul lebar", sectionTitle: "Tentang aplikasi" });
    kicker(s, "Cara kerja");
    s.addText("Dari lereng sampai ke HP warga", { placeholder: "title" });
    const steps = [
      [icons.tower, "Alat membaca lereng", "Alat EWS mengukur kelembapan tanah, hujan, dan kemiringan tanah."],
      [icons.server, "Server menilai status", "Bacaan dikirim ke server desa, lalu dinilai: Normal, Waspada, atau Awas."],
      [icons.map, "Aplikasi menampilkan", "Peta, bacaan sensor, dan catatan diperbarui tiap 10 detik."],
      [icons.bell, "HP memberi tanda", "Saat status berubah, HP menampilkan notifikasi dengan suara khusus."],
    ];
    const colW = 2.5, gap = 0.58, top = 2.25;
    steps.forEach(([data, head, body], i) => {
      const x = LEFT + i * (colW + gap);
      card(s, x, top, colW, 3.75, `Kartu langkah ${i + 1}`);
      tile(s, x + 0.3, top + 0.32, 0.9, data, BLUE, `Ikon langkah ${i + 1}`);
      text(s, `Langkah ${i + 1}`, { x: x + 0.3, y: top + 1.45, w: colW - 0.6, h: 0.28, fontSize: 12, bold: true, color: CYAN, objectName: `Label langkah ${i + 1}` });
      text(s, head, { x: x + 0.3, y: top + 1.76, w: colW - 0.5, h: 0.62, fontSize: 16, bold: true, color: WHITE, objectName: `Judul langkah ${i + 1}` });
      text(s, body, { x: x + 0.3, y: top + 2.42, w: colW - 0.5, h: 1.2, fontSize: 14, color: MUTED, objectName: `Isi langkah ${i + 1}` });
      if (i < steps.length - 1) {
        s.addImage({ data: icons.arrow, x: x + colW + 0.14, y: top + 1.72, w: 0.3, h: 0.3, objectName: `Panah ${i + 1}` });
      }
    });
    text(s, "Status ditentukan server, jadi semua warga melihat status yang sama.", {
      x: LEFT, y: 6.33, w: 11.4, h: 0.34, fontSize: 14, color: WHITE, objectName: "Catatan status",
    });
    s.addNotes(
      "Jelaskan urutannya pelan-pelan. Warga tidak perlu melakukan apa pun supaya data masuk: alat mengirim sendiri, server menilai, aplikasi menampilkan. Status ditentukan server, bukan oleh HP masing-masing, jadi semua warga melihat status yang sama."
    );
  }

  // ============ 6. Tiga menu ============
  pres.addSection({ title: "Menu aplikasi" });
  {
    const s = pres.addSlide({ masterName: "Judul lebar", sectionTitle: "Menu aplikasi" });
    kicker(s, "Menu aplikasi");
    s.addText("Tiga menu utama", { placeholder: "title" });
    const menus = [
      ["beranda", "Beranda", "Peta desa dan catatan terbaru"],
      ["sensor2", "Sensor", "Bacaan alat yang terus diperbarui"],
      ["lapor", "Lapor", "Melaporkan tanda longsor"],
    ];
    const ph = 3.75, pw = ph * PHONE_RATIO;
    menus.forEach(([shot, head, body], i) => {
      const cx = 2.75 + i * 3.92;
      phone(s, shot, cx - pw / 2, 2.05, ph, { altText: `Layar menu ${head}` });
      text(s, head, { x: cx - 1.7, y: 5.92, w: 3.4, h: 0.38, fontSize: 18, bold: true, color: WHITE, align: "center", objectName: `Nama menu ${head}` });
      text(s, body, { x: cx - 1.7, y: 6.32, w: 3.4, h: 0.32, fontSize: 14, color: WHITE, align: "center", objectName: `Isi menu ${head}` });
    });
    s.addNotes(
      "Menu ada di bagian bawah layar. Beranda untuk melihat keadaan sekarang, Sensor untuk melihat angka dari alat, Lapor untuk warga yang melihat tanda longsor. Tiga slide berikutnya membahas satu per satu."
    );
  }

  // ============ 7. Beranda ============
  {
    const s = pres.addSlide({ masterName: "Judul kanan", sectionTitle: "Menu aplikasi" });
    kicker(s, "Menu 1 dari 3", 6.55);
    s.addText("Beranda: peta desa", { placeholder: "title" });
    phone(s, "legend", LEFT, 0.95, 5.6, { altText: "Beranda dengan keterangan warna area EWS" });
    phone(s, "detail", 3.3, 1.6, 4.95, { altText: "Rincian bacaan alat EWS-02" });
    const rows = [
      ["01", "Area tiap alat di peta", "Peta satelit menunjukkan letak EWS-01 dan EWS-02. Warna area mengikuti status alat."],
      ["02", "Catatan terbaru", "Setiap perubahan status tercatat dengan jam dan penyebabnya."],
      ["03", "Ketuk alat untuk rinciannya", "Bacaan terakhir tiap sensor muncul tanpa pindah halaman."],
    ];
    rows.forEach(([n, head, body], i) => {
      const y = 2.3 + i * 1.42;
      numberTile(s, 6.55, y, n);
      headed(s, 7.42, y, 5.3, head, body, 0.75);
    });
    s.addNotes(
      "Tunjukkan langsung di HP bila memungkinkan. Jelaskan tombol Keterangan di kanan atas peta: hijau Normal, kuning Waspada, merah Awas, putih bergaris berarti alat tidak mengirim data."
    );
  }

  // ============ 8. Sensor ============
  {
    const s = pres.addSlide({ masterName: "Judul kiri", sectionTitle: "Menu aplikasi" });
    kicker(s, "Menu 2 dari 3");
    s.addText("Sensor: bacaan alat", { placeholder: "title" });
    const sensors = [
      [icons.tint, "Kelembapan tanah", "Seberapa basah tanah di lereng."],
      [icons.rain, "Intensitas hujan", "Seberapa deras hujan di lokasi alat."],
      [icons.slope, "Kemiringan", "Perubahan miring tanah, tanda lereng bergerak."],
      [icons.wind, "Kelembapan udara", "Hanya informasi, tidak mengubah status."],
    ];
    const cw = 3.3, ch = 1.62;
    sensors.forEach(([data, head, body], i) => {
      const x = LEFT + (i % 2) * (cw + 0.25);
      const y = 2.25 + Math.floor(i / 2) * (ch + 0.25);
      card(s, x, y, cw, ch, `Kartu ${head}`);
      tile(s, x + 0.25, y + 0.25, 0.56, data, BLUE, `Ikon ${head}`);
      text(s, head, { x: x + 0.98, y: y + 0.25, w: cw - 1.15, h: 0.56, fontSize: 16, bold: true, color: WHITE, valign: "middle", objectName: `Judul: ${head}` });
      text(s, body, { x: x + 0.25, y: y + 0.95, w: cw - 0.5, h: 0.58, fontSize: 14, color: MUTED, objectName: `Isi: ${head}` });
    });
    text(s, "Diperbarui tiap 10 detik. Bila alat diam 15 menit, bacaannya ditandai sebagai data lama.", {
      x: LEFT, y: 6.02, w: 6.85, h: 0.6, fontSize: 14, color: WHITE, objectName: "Catatan pembaruan",
    });
    phone(s, "sensor", 8.15, 1.2, 4.9, { altText: "Menu Sensor: status Waspada dan penyebabnya" });
    phone(s, "sensor2", 10.5, 1.65, 4.9, { altText: "Menu Sensor: empat kartu bacaan" });
    s.addNotes(
      "Empat angka ini berasal dari alat di lereng. Tiga yang pertama ikut menentukan status. Kelembapan udara hanya informasi. Jelaskan tulisan 'Data lama': artinya alat sedang tidak mengirim, jadi angka itu bukan keadaan sekarang."
    );
  }

  // ============ 9. Lapor ============
  {
    const s = pres.addSlide({ masterName: "Judul kanan", sectionTitle: "Menu aplikasi" });
    kicker(s, "Menu 3 dari 3", 6.55);
    s.addText("Lapor: laporan warga", { placeholder: "title" });
    phone(s, "lapor_isi", LEFT, 0.95, 5.6, { altText: "Formulir laporan dengan cerita bahasa Jawa" });
    phone(s, "hasil1", 3.3, 1.6, 4.95, { altText: "Hasil analisis: cerita dibakukan ke bahasa Indonesia" });
    const rows = [
      ["01", "Foto dari tempat aman", "Boleh sampai 5 foto. Aplikasi memberi tahu bila foto buram atau gelap."],
      ["02", "Cerita dengan bahasa sehari-hari", "Bahasa Jawa juga bisa, misalnya \"lemah e bengkah neng mburi omah pak RT\"."],
      ["03", "Aplikasi merapikan laporan", "Cerita dibakukan ke bahasa Indonesia, lalu jenis tanda dan tempatnya dikenali."],
      ["04", "Kirim ke petugas", "Laporan, foto, dan lokasi HP dikirim lewat WhatsApp."],
    ];
    rows.forEach(([n, head, body], i) => {
      const y = 2.15 + i * 1.12;
      numberTile(s, 6.55, y, n);
      headed(s, 7.42, y, 5.3, head, body, 0.6);
    });
    s.addNotes(
      "Ini fitur unggulan. Warga cukup bercerita seperti biasa, tidak perlu bahasa resmi. Contoh di layar: 'lemah e bengkah neng mburi omah pak RT, saiki tambah amba' menjadi 'Tanahnya retak di belakang rumah Pak RT, sekarang makin lebar'. Ingatkan: jangan mendekati lereng hanya untuk mengambil foto."
    );
  }

  // ============ 10. Status ============
  {
    const s = pres.addSlide({ masterName: "Judul kiri", sectionTitle: "Menu aplikasi" });
    kicker(s, "Status dan notifikasi");
    s.addText("Arti tiap status", { placeholder: "title" });
    const statuses = [
      [icons.check, C.accent3, "Normal", "Semua bacaan alat masih di bawah batas waspada."],
      [icons.warn, C.accent4, "Waspada", "Tanah mulai jenuh air, hujan deras, atau lereng mulai bergerak. Hindari lereng dan siapkan jalur evakuasi."],
      [icons.cross, C.accent5, "Awas", "Kabel alat EWS putus atau sudah disetujui admin. Segera menjauh dari lereng."],
      [icons.question, C.accent6, "Tidak ada data", "Alat berhenti mengirim. Kondisi tidak diketahui, jangan anggap sudah aman."],
    ];
    const cw = 3.7, ch = 2.05;
    statuses.forEach(([data, color, head, body], i) => {
      const x = LEFT + (i % 2) * (cw + 0.25);
      const y = 2.2 + Math.floor(i / 2) * (ch + 0.25);
      card(s, x, y, cw, ch, `Kartu ${head}`);
      s.addShape(pres.shapes.OVAL, { x: x + 0.25, y: y + 0.25, w: 0.56, h: 0.56, fill: { color }, line: { color, width: 0 }, objectName: `Tanda ${head} latar` });
      s.addImage({ data, x: x + 0.41, y: y + 0.41, w: 0.24, h: 0.24, objectName: `Tanda ${head}` });
      text(s, head, { x: x + 0.98, y: y + 0.25, w: cw - 1.15, h: 0.56, fontSize: 18, bold: true, color: WHITE, valign: "middle", objectName: `Judul: ${head}` });
      text(s, body, { x: x + 0.25, y: y + 0.93, w: cw - 0.5, h: 1.05, fontSize: 14, color: MUTED, objectName: `Isi: ${head}` });
    });
    phone(s, "notif", 9.55, 0.95, 5.6, { altText: "Halaman Notifikasi dengan riwayat peringatan" });
    s.addNotes(
      "Yang paling penting: 'Tidak ada data' bukan berarti aman. Alat bisa mati justru saat tanah bergerak. Riwayat peringatan bisa dilihat lewat ikon lonceng di kanan atas pada semua menu."
    );
  }

  // ============ 11. Kinerja ============
  pres.addSection({ title: "Kinerja dan penutup" });
  {
    const s = pres.addSlide({ masterName: "Judul lebar", sectionTitle: "Kinerja dan penutup" });
    kicker(s, "Kinerja aplikasi");
    s.addText("Sejauh mana aplikasinya berjalan", { placeholder: "title" });
    const stats = [
      ["10 detik", "jarak pembaruan data dari server"],
      ["15 menit", "alat diam, langsung ditandai"],
      ["95", "pemeriksaan otomatis lolos"],
      ["1 dari 2", "alat sudah mengirim data"],
    ];
    const sw = 2.72, gap = 0.26;
    stats.forEach(([value, label], i) => {
      const x = LEFT + i * (sw + gap);
      text(s, value, { x, y: 2.1, w: sw, h: 0.8, fontSize: 40, bold: true, color: CYAN, valign: "middle", objectName: `Angka ${value}` });
      text(s, label, { x, y: 2.95, w: sw, h: 0.5, fontSize: 14, color: WHITE, objectName: `Label ${value}` });
    });
    const half = (W - LEFT * 2 - 0.3) / 2;
    const lists = [
      [icons.check, "Sudah berjalan", [
        "Data asli dari server desa tampil di peta dan menu Sensor",
        "Laporan bahasa Jawa dibakukan langsung di HP",
        "Foto buram atau gelap dikenali sebelum dikirim",
      ]],
      [icons.clock, "Masih disiapkan", [
        "EWS-01 di Jomparang belum mengirim data",
        "Pengenalan isi foto otomatis menunggu contoh foto lapangan",
        "Kamus bahasa Jawa perlu diperiksa penutur setempat",
      ]],
    ];
    lists.forEach(([data, head, items], i) => {
      const x = LEFT + i * (half + 0.3);
      card(s, x, 3.75, half, 2.75, `Kartu ${head}`);
      tile(s, x + 0.3, 3.98, 0.5, data, i === 0 ? C.accent3 : C.accent6, `Ikon ${head}`);
      text(s, head, { x: x + 0.98, y: 3.98, w: half - 1.2, h: 0.5, fontSize: 18, bold: true, color: WHITE, valign: "middle", objectName: `Judul: ${head}` });
      text(s, items.map((t, j) => ({ text: t, options: { bullet: true, breakLine: j < items.length - 1 } })), {
        x: x + 0.3, y: 4.68, w: half - 0.6, h: 1.7, fontSize: 14, color: WHITE, paraSpaceAfter: 6, objectName: `Daftar: ${head}`,
      });
    });
    s.addNotes(
      "Sampaikan apa adanya. Yang sudah berjalan: data asli dari alat EWS-02, peta, bacaan sensor, dan laporan warga. Yang masih disiapkan: alat kedua, pengenalan isi foto, dan kamus bahasa Jawa yang perlu bantuan warga untuk diperiksa. Ajak warga ikut memberi contoh kata dan foto."
    );
  }

  // ============ 12. Penutup ============
  {
    const s = pres.addSlide({ masterName: "Sampul", sectionTitle: "Kinerja dan penutup" });
    s.addImage({
      path: path.join(BRAND, "logo_wordmark_light.png"), x: LEFT, y: 1.35, w: 3.6, h: 3.6 * (228 / 686),
      altText: "Logo EWS Lumeneng", objectName: "Logo",
    });
    s.addText("Terima kasih", { placeholder: "title" });
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, {
      x: LEFT, y: 4.2, w: 5.75, h: 1.75, rectRadius: 0.18, fill: { color: C.text1, transparency: 45 },
      line: { type: "none" }, objectName: "Kartu pesan keselamatan",
    });
    s.addImage({ data: icons.shield, x: LEFT + 0.3, y: 4.865, w: 0.42, h: 0.42, objectName: "Ikon keselamatan" });
    text(s, "Aplikasi ini alat bantu pemantauan warga, bukan peringatan resmi BPBD. Saat ragu, utamakan keselamatan dan ikuti arahan perangkat desa.", {
      x: LEFT + 0.95, y: 4.4, w: 4.55, h: 1.35, fontSize: 14, color: WHITE, valign: "middle", objectName: "Pesan keselamatan",
    });
    phone(s, "beranda", 7.15, 1.25, 5.0, { rotate: -7, altText: "Layar Beranda aplikasi" });
    phone(s, "sensor", 10.15, 1.0, 5.0, { rotate: 7, altText: "Layar Sensor aplikasi" });
    s.addNotes(
      "Tutup dengan pesan keselamatan: aplikasi membantu, tetapi keputusan tetap pada warga dan perangkat desa. Buka sesi tanya jawab, lalu bantu warga memasang aplikasinya."
    );
  }

  await pres.writeFile({ fileName: OUT });
  await applyTheme(OUT, THEME);
  console.log("ditulis:", OUT);
})();
