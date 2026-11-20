// Membuat assets/peta/batas_desa.geojson dan zona_longsor.geojson dari dua
// gambar di dokumen "Kajian Pemetaan Bencana Desa Lumeneng 2024" (.docx):
// Peta Rawan Longsor (word/media/image52.jpg, 578x409) dan Peta Sumber Air
// (word/media/image39.png, 2188x2147, dipakai untuk batas desa karena lebih
// tajam). Buka .docx sebagai zip untuk mengambilnya.
//
//   dart run tool/peta_dari_kajian.dart image52.jpg image39.png assets/peta //     periksa.png
//
// periksa.png berisi garis poligon di atas peta asli (batas desa magenta) untuk
// dicocokkan dengan mata. Jangan simpan di assets/peta, nanti ikut dibundel.
//
// Luas hasil terakhir dibanding legenda kajian (ha): aman 22,5 (38,7), agak
// rawan 447,1 (448,5), rawan 402,2 (383), sangat rawan 2,3 (2,1), total 874,2
// (872,3). Aman paling kurang karena bintik biru kecil di gambar JPEG luntur.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Posisi kontinu garis grid 109.560 BT dan -7.180 LS, dan piksel per derajat.
/// Diukur dari pusat silang grid di bingkai peta (cross.dart).
class Geo {
  const Geo(this.x0, this.y0, this.pxLon, this.pxLat);
  final double x0, y0, pxLon, pxLat;
  double lon(num x) => 109.560 + (x - x0) / pxLon;
  double lat(num y) => -7.180 - (y - y0) / pxLat;
  double x(double lon) => x0 + (lon - 109.560) * pxLon;
  double y(double lat) => y0 + (-7.180 - lat) * pxLat;
}

const geo52 = Geo(46.30, 137.85, 7926.0, 7932.0);
const geo39 = Geo(207.21, 705.50, 43553.5, 43577.5);

const outside = 0, unknown = 9;
const classNames = ['', 'aman', 'agak_rawan', 'rawan', 'sangat_rawan'];
const legendHa = [0, 38.7, 448.5, 383.0, 2.1];

// Meter per derajat di sekitar -7.185.
const mLon = 110446.0, mLat = 110580.0;

void main(List<String> args) {
  final im52 = img.decodeImage(File(args[0]).readAsBytesSync())!;
  final im39 = img.decodeImage(File(args[1]).readAsBytesSync())!;
  final outDir = args[2];
  final checkImage = args.length > 3 ? args[3] : 'periksa.png';

  // 1. Batas desa dari peta resolusi tinggi.
  final w39 = im39.width, h39 = im39.height;
  final mask39 = villageMask(im39);
  final villageRings = traceRings(mask39, w39, h39, 1);
  villageRings.sort(
    (a, b) => ringArea(b, w39).abs().compareTo(ringArea(a, w39).abs()),
  );
  final outer = villageRings.first;
  print(
    'batas desa: ${villageRings.length} cincin, terbesar ${outer.length} titik',
  );
  final boundaryPx = simplifyLoop(toPoints(outer, w39), 1.0);
  final boundary = [
    for (final p in boundaryPx) [geo39.lon(p.x), geo39.lat(p.y)],
  ];
  print(
    'batas disederhanakan: ${boundary.length} titik, luas ${(polygonAreaM2(boundary) / 10000).toStringAsFixed(1)} ha (kajian 884,6)',
  );

  // 2. Kelas zona dari peta rawan longsor.
  final w = im52.width, h = im52.height;
  final cls = Int8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final lon = geo52.lon(x + 0.5), lat = geo52.lat(y + 0.5);
      final mx = geo39.x(lon).floor(), my = geo39.y(lat).floor();
      final inside =
          mx >= 0 &&
          my >= 0 &&
          mx < w39 &&
          my < h39 &&
          mask39[my * w39 + mx] == 1;
      if (!inside) continue;
      final p = im52.getPixel(x, y);
      var c = classify(p.r, p.g, p.b);
      // Merah tua di luar Sikudi–Jomparang–Sikembang adalah tepi garis
      // permukiman atau teks di atas merah, bukan sangat rawan: potongan
      // peta per dukuh yang lebih tajam (image53–61) hanya menunjukkan merah
      // tua di sekitar Jomparang.
      if (c == 4 &&
          !(lon > 109.5857 &&
              lon < 109.5958 &&
              lat < -7.1790 &&
              lat > -7.1879)) {
        c = unknown;
      }
      cls[y * w + x] = c;
    }
  }
  var unknownCount = 0;
  for (final c in cls) {
    if (c == unknown) unknownCount++;
  }
  fillUnknown(cls, w, h);
  // Bintik satu piksel kebanyakan sisa kompresi JPEG.
  final specks = absorbSmall(
    cls,
    w,
    h,
    (c, size) => size < 2 || (c == 4 && size < 3),
  );
  print('piksel diisi dari tetangga: $unknownCount, bintik dilebur: $specks');
  printAreas('raster', [
    for (var c = 0; c <= 4; c++)
      cls.where((v) => v == c).length *
          (mLon / geo52.pxLon) *
          (mLat / geo52.pxLat),
  ]);

  // 3. Poligon per kelas dengan garis batas bersama yang disederhanakan sekali.
  final nodes = findNodes(cls, w, h);
  final arcCache = <String, List<Point<double>>>{};
  final features = <Map<String, Object>>[];
  final areas = List.filled(5, 0.0);
  var vertexCount = 0;
  for (var c = 1; c <= 4; c++) {
    final comp = labelComponents(cls, w, h, c);
    final rings = traceRings(cls, w, h, c);
    final polys =
        <int, ({List<List<double>>? outer, List<List<List<double>>> holes})>{};
    for (final ring in rings) {
      final area = ringArea(
        ring,
        w + 0,
      ); // area in pixel coords, sign = orientation
      final pixel = rightPixel(ring, w);
      final id = comp[pixel];
      final simplified = simplifyRing(ring, w, nodes, arcCache, 0.75);
      if (simplified.length < 4 || pointsArea(simplified).abs() < 0.25) {
        continue;
      }
      // GeoJSON: cincin luar berlawanan jarum jam, lubang searah jarum jam.
      final coords = [
        for (final p in simplified.reversed)
          [round6(geo52.lon(p.x)), round6(geo52.lat(p.y))],
      ];
      vertexCount += coords.length;
      final entry = polys[id] ?? (outer: null, holes: <List<List<double>>>[]);
      if (area > 0) {
        polys[id] = (outer: coords, holes: entry.holes);
      } else {
        entry.holes.add(coords);
        polys[id] = entry;
      }
    }
    final multi = <List<List<List<double>>>>[];
    for (final p in polys.values) {
      if (p.outer == null) continue;
      multi.add([p.outer!, ...p.holes]);
      areas[c] +=
          polygonAreaM2(p.outer!) -
          p.holes.fold(0.0, (s, hole) => s + polygonAreaM2(hole));
    }
    features.add({
      'type': 'Feature',
      'properties': {'kelas': classNames[c]},
      'geometry': {'type': 'MultiPolygon', 'coordinates': multi},
    });
    print('${classNames[c]}: ${multi.length} poligon');
  }
  printAreas('poligon', areas);
  print('jumlah titik zona: $vertexCount');

  const source =
      'Ditelusuri dari gambar Peta Rawan Longsor dan Peta Sumber Air dalam '
      'Kajian Pemetaan Bencana Desa Lumeneng 2024 (Tim Pemetaan LPBI NU Kab. '
      'Pekalongan dan Ringan Tangan Foundation). Bukan data GIS asli; ganti '
      'dengan ekspor shapefile tim pemetaan bila sudah ada.';
  File('$outDir/zona_longsor.geojson').writeAsStringSync(
    jsonEncode({
      'type': 'FeatureCollection',
      'keterangan': source,
      'features': features,
    }),
  );
  File('$outDir/batas_desa.geojson').writeAsStringSync(
    jsonEncode({
      'type': 'FeatureCollection',
      'keterangan': source,
      'features': [
        {
          'type': 'Feature',
          'properties': {'nama': 'Desa Lumeneng'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                for (final p in boundary.reversed) [round6(p[0]), round6(p[1])],
              ],
            ],
          },
        },
      ],
    }),
  );

  // 4. Gambar periksa: garis poligon di atas peta asli, batas desa magenta.
  const s = 3;
  final dbg = img.copyResize(
    im52,
    width: w * s,
    height: h * s,
    interpolation: img.Interpolation.nearest,
  );
  final black = img.ColorRgb8(0, 0, 0), magenta = img.ColorRgb8(255, 0, 255);
  for (final f in features) {
    final multi = (f['geometry'] as Map)['coordinates'] as List;
    for (final poly in multi) {
      for (final ring in poly as List) {
        drawRing(dbg, ring as List, geo52, s, black);
      }
    }
  }
  drawRing(dbg, boundary, geo52, s, magenta);
  File(checkImage).writeAsBytesSync(img.encodePng(dbg));
}

double round6(double v) => (v * 1e6).round() / 1e6;

void drawRing(img.Image dbg, List ring, Geo geo, int s, img.Color color) {
  for (var i = 0; i + 1 < ring.length; i++) {
    final a = ring[i] as List, b = ring[i + 1] as List;
    img.drawLine(
      dbg,
      x1: (geo.x(a[0]) * s).round(),
      y1: (geo.y(a[1]) * s).round(),
      x2: (geo.x(b[0]) * s).round(),
      y2: (geo.y(b[1]) * s).round(),
      color: color,
    );
  }
}

void printAreas(String label, List<double> m2) {
  final total = m2.sublist(1).reduce((a, b) => a + b);
  final parts = [
    for (var c = 1; c <= 4; c++)
      '${classNames[c]} ${(m2[c] / 10000).toStringAsFixed(1)} (${legendHa[c]})',
  ];
  print(
    '$label ha: ${parts.join(', ')}, total ${(total / 10000).toStringAsFixed(1)} (872,3)',
  );
}

double polygonAreaM2(List ring) {
  var a = 0.0;
  for (var i = 0; i + 1 < ring.length; i++) {
    final p = ring[i] as List, q = ring[i + 1] as List;
    a += (p[0] * mLon) * (q[1] * mLat) - (q[0] * mLon) * (p[1] * mLat);
  }
  return (a / 2).abs();
}

/// Warna legenda: aman (95,192,232), agak rawan (250,205,25), rawan
/// (244,38,18), sangat rawan (140,4,8). Arsiran permukiman menggelapkan warna
/// zona di bawahnya, jadi yang dilihat rona, bukan terang.
int classify(num r, num g, num b) {
  final mx = max(r, max(g, b)).toDouble(), mn = min(r, min(g, b)).toDouble();
  final v = mx / 255, s = mx == 0 ? 0.0 : (mx - mn) / mx;
  if (s < 0.3 || v < 0.25) return unknown;
  final d = mx - mn;
  double hue;
  if (mx == r) {
    hue = 60 * (((g - b) / d) % 6);
  } else if (mx == g) {
    hue = 60 * ((b - r) / d + 2);
  } else {
    hue = 60 * ((r - g) / d + 4);
  }
  if (hue < 0) hue += 360;
  // Campuran setengah kuning setengah biru jatuh di rona ±82°.
  if (hue >= 82 && hue <= 250) return 1;
  if (hue >= 30 && hue < 82) return 2;
  if (hue < 30 || hue >= 330) return v < 0.62 ? 4 : 3;
  return unknown;
}

Uint8List villageMask(img.Image im) {
  final w = im.width, h = im.height;
  final sat = Uint8List(w * h);
  const margin = 12;
  for (var y = margin; y < h - margin; y++) {
    for (var x = margin; x < w - margin; x++) {
      final p = im.getPixel(x, y);
      final r = p.r, g = p.g, b = p.b;
      final white = r > 225 && g > 225 && b > 225;
      final cyan = g > 170 && b > 170 && r < 160 && g - r > 60;
      final orange = r > 200 && g > 90 && g < 210 && b < 110 && r - b > 120;
      if (!white && !cyan && !orange) sat[y * w + x] = 1;
    }
  }
  // Garis sungai memotong desa jadi beberapa bagian besar; teks dan silang
  // grid di bingkai jadi bagian kecil yang dibuang.
  final comp = labelComponents(sat, w, h, 1);
  final sizes = <int, int>{};
  for (final c in comp) {
    if (c >= 0) sizes[c] = (sizes[c] ?? 0) + 1;
  }
  for (var i = 0; i < w * h; i++) {
    if (sat[i] == 1 && sizes[comp[i]]! < 2000) sat[i] = 0;
  }
  var mask = erode(dilate(sat, w, h, 3), w, h, 3);
  mask = fillHoles(mask, w, h);
  // Sisakan bagian terbesar.
  final comp2 = labelComponents(mask, w, h, 1);
  final sizes2 = <int, int>{};
  for (final c in comp2) {
    if (c >= 0) sizes2[c] = (sizes2[c] ?? 0) + 1;
  }
  final biggest = sizes2.entries
      .reduce((a, b) => a.value >= b.value ? a : b)
      .key;
  for (var i = 0; i < w * h; i++) {
    mask[i] = comp2[i] == biggest ? 1 : 0;
  }
  return mask;
}

Uint8List dilate(Uint8List m, int w, int h, int r) => _morph(m, w, h, r, true);
Uint8List erode(Uint8List m, int w, int h, int r) => _morph(m, w, h, r, false);

Uint8List _morph(Uint8List m, int w, int h, int r, bool grow) {
  final tmp = Uint8List(w * h), out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = grow ? 0 : 1;
      for (var k = -r; k <= r; k++) {
        final xx = x + k;
        final s = xx < 0 || xx >= w ? 0 : m[y * w + xx];
        if (grow ? s == 1 : s == 0) {
          v = grow ? 1 : 0;
          break;
        }
      }
      tmp[y * w + x] = v;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = grow ? 0 : 1;
      for (var k = -r; k <= r; k++) {
        final yy = y + k;
        final s = yy < 0 || yy >= h ? 0 : tmp[yy * w + x];
        if (grow ? s == 1 : s == 0) {
          v = grow ? 1 : 0;
          break;
        }
      }
      out[y * w + x] = v;
    }
  }
  return out;
}

Uint8List fillHoles(Uint8List m, int w, int h) {
  final outsideMark = Uint8List(w * h);
  final stack = <int>[];
  for (var x = 0; x < w; x++) {
    stack
      ..add(x)
      ..add((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    stack
      ..add(y * w)
      ..add(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    if (outsideMark[i] == 1 || m[i] == 1) continue;
    outsideMark[i] = 1;
    final x = i % w, y = i ~/ w;
    if (x > 0) stack.add(i - 1);
    if (x < w - 1) stack.add(i + 1);
    if (y > 0) stack.add(i - w);
    if (y < h - 1) stack.add(i + w);
  }
  final out = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    out[i] = outsideMark[i] == 1 ? 0 : 1;
  }
  return out;
}

/// Label komponen 4-tetangga untuk sel bernilai [c]; sel lain -1.
Int32List labelComponents(List<int> grid, int w, int h, int c) {
  final comp = Int32List(w * h)..fillRange(0, w * h, -1);
  var id = 0;
  final stack = <int>[];
  for (var i = 0; i < w * h; i++) {
    if (grid[i] != c || comp[i] >= 0) continue;
    comp[i] = id;
    stack.add(i);
    while (stack.isNotEmpty) {
      final j = stack.removeLast();
      final x = j % w, y = j ~/ w;
      if (x > 0 && grid[j - 1] == c && comp[j - 1] < 0) {
        comp[j - 1] = id;
        stack.add(j - 1);
      }
      if (x < w - 1 && grid[j + 1] == c && comp[j + 1] < 0) {
        comp[j + 1] = id;
        stack.add(j + 1);
      }
      if (y > 0 && grid[j - w] == c && comp[j - w] < 0) {
        comp[j - w] = id;
        stack.add(j - w);
      }
      if (y < h - 1 && grid[j + w] == c && comp[j + w] < 0) {
        comp[j + w] = id;
        stack.add(j + w);
      }
    }
    id++;
  }
  return comp;
}

/// Piksel belum diketahui di dalam desa diisi kelas terbanyak di sekitarnya.
void fillUnknown(Int8List cls, int w, int h) {
  var changed = true;
  while (changed) {
    changed = false;
    final next = Int8List.fromList(cls);
    for (var i = 0; i < w * h; i++) {
      if (cls[i] != unknown) continue;
      final best = _majority(cls, w, h, i, (c) => c >= 1 && c <= 4);
      if (best > 0) {
        next[i] = best;
        changed = true;
      }
    }
    cls.setAll(0, next);
  }
}

int _majority(Int8List cls, int w, int h, int i, bool Function(int) accept) {
  final x = i % w, y = i ~/ w;
  final votes = List.filled(5, 0);
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      if (dx == 0 && dy == 0) continue;
      final nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      final c = cls[ny * w + nx];
      if (accept(c)) votes[c]++;
    }
  }
  var best = 0, bestVotes = 0;
  for (var c = 1; c <= 4; c++) {
    if (votes[c] > bestVotes) {
      bestVotes = votes[c];
      best = c;
    }
  }
  return best;
}

/// Komponen kecil dilebur ke kelas tetangga terbanyak di sekelilingnya.
int absorbSmall(
  Int8List cls,
  int w,
  int h,
  bool Function(int c, int size) small,
) {
  var merged = 0;
  for (var c = 1; c <= 4; c++) {
    final comp = labelComponents(cls, w, h, c);
    final members = <int, List<int>>{};
    for (var i = 0; i < w * h; i++) {
      if (comp[i] >= 0) (members[comp[i]] ??= []).add(i);
    }
    for (final cells in members.values) {
      if (!small(c, cells.length)) continue;
      final votes = List.filled(5, 0);
      for (final i in cells) {
        final x = i % w, y = i ~/ w;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final n = cls[ny * w + nx];
            if (n >= 1 && n <= 4 && n != c) votes[n]++;
          }
        }
      }
      var best = 0, bestVotes = 0;
      for (var k = 1; k <= 4; k++) {
        if (votes[k] > bestVotes) {
          bestVotes = votes[k];
          best = k;
        }
      }
      if (best == 0) continue;
      for (final i in cells) {
        cls[i] = best;
      }
      merged++;
    }
  }
  return merged;
}

// Arah: 0 timur, 1 selatan, 2 barat, 3 utara (y ke bawah).
const _dx = [1, 0, -1, 0], _dy = [0, 1, 0, -1];

/// Cincin batas sel bernilai [c], titik sudut sebagai id y*(w+1)+x. Sel
/// selalu di kanan arah jalan, jadi cincin luar searah jarum jam di gambar
/// (luas bertanda positif) dan lubang sebaliknya. Di titik pelana belok
/// kanan, sama dengan komponen 4-tetangga.
List<List<int>> traceRings(List<int> grid, int w, int h, int c) {
  final vw = w + 1;
  final out = Uint8List(vw * (h + 1));
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (grid[y * w + x] != c) continue;
      if (y == 0 || grid[(y - 1) * w + x] != c) out[y * vw + x] |= 1;
      if (x == w - 1 || grid[y * w + x + 1] != c) out[y * vw + x + 1] |= 2;
      if (y == h - 1 || grid[(y + 1) * w + x] != c) {
        out[(y + 1) * vw + x + 1] |= 4;
      }
      if (x == 0 || grid[y * w + x - 1] != c) out[(y + 1) * vw + x] |= 8;
    }
  }
  int pick(int bits, int incoming) {
    final right = (incoming + 1) % 4, left = (incoming + 3) % 4;
    if (bits & (1 << right) != 0) return right;
    if (bits & (1 << incoming) != 0) return incoming;
    if (bits & (1 << left) != 0) return left;
    return -1;
  }

  final rings = <List<int>>[];
  for (final saddlePass in [false, true]) {
    for (var v = 0; v < out.length; v++) {
      while (out[v] != 0) {
        final bits = out[v];
        final isSaddle = bits == 5 || bits == 10;
        if (isSaddle && !saddlePass) break;
        var d = 0;
        while (bits & (1 << d) == 0) {
          d++;
        }
        final start = v, startDir = d;
        final ring = <int>[];
        var cur = v;
        while (true) {
          ring.add(cur);
          out[cur] &= ~(1 << d);
          final x = cur % vw + _dx[d], y = cur ~/ vw + _dy[d];
          cur = y * vw + x;
          if (cur == start) {
            final next = pick(out[cur] | (1 << startDir), d);
            if (next == startDir) break;
            d = next;
            continue;
          }
          d = pick(out[cur], d);
          if (d < 0) throw StateError('cincin putus di $cur');
        }
        rings.add(ring);
      }
    }
  }
  return rings;
}

double ringArea(List<int> ring, int w) {
  final vw = w + 1;
  var a = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final p = ring[i], q = ring[(i + 1) % ring.length];
    a += (p % vw) * (q ~/ vw) - (q % vw) * (p ~/ vw);
  }
  return a / 2;
}

double pointsArea(List<Point<double>> pts) {
  var a = 0.0;
  for (var i = 0; i + 1 < pts.length; i++) {
    a += pts[i].x * pts[i + 1].y - pts[i + 1].x * pts[i].y;
  }
  return a / 2;
}

/// Sel di kanan sisi pertama cincin.
int rightPixel(List<int> ring, int w) {
  final vw = w + 1;
  final a = ring[0], b = ring[1];
  final ax = a % vw, ay = a ~/ vw, bx = b % vw, by = b ~/ vw;
  final (px, py) = switch ((bx - ax, by - ay)) {
    (1, 0) => (ax, ay),
    (0, 1) => (ax - 1, ay),
    (-1, 0) => (ax - 1, ay - 1),
    _ => (ax, ay - 1),
  };
  return py * w + px;
}

List<Point<double>> toPoints(List<int> ring, int w) => [
  for (final v in ring)
    Point((v % (w + 1)).toDouble(), (v ~/ (w + 1)).toDouble()),
];

/// Titik sudut yang dikelilingi tiga kelas atau lebih, atau dua kelas
/// bersilang. Garis batas dipotong di sini supaya tiap potongan dipakai
/// bersama oleh dua kelas yang dipisahkannya.
Uint8List findNodes(Int8List cls, int w, int h) {
  final vw = w + 1;
  final nodes = Uint8List(vw * (h + 1));
  int at(int x, int y) =>
      x < 0 || y < 0 || x >= w || y >= h ? 0 : cls[y * w + x];
  for (var y = 0; y <= h; y++) {
    for (var x = 0; x <= w; x++) {
      final a = at(x - 1, y - 1),
          b = at(x, y - 1),
          c = at(x - 1, y),
          d = at(x, y);
      final distinct = {a, b, c, d}.length;
      final saddle = distinct == 2 && a == d && b == c && a != b;
      if (distinct >= 3 || saddle) nodes[y * vw + x] = 1;
    }
  }
  return nodes;
}

List<Point<double>> simplifyRing(
  List<int> ring,
  int w,
  Uint8List nodes,
  Map<String, List<Point<double>>> cache,
  double tol,
) {
  final vw = w + 1;
  Point<double> pt(int v) => Point((v % vw).toDouble(), (v ~/ vw).toDouble());
  final firstNode = ring.indexWhere((v) => nodes[v] == 1);
  if (firstNode < 0) {
    // Pulau tanpa simpul: satu garis tertutup, dibakukan dari id terkecil.
    var m = 0;
    for (var i = 1; i < ring.length; i++) {
      if (ring[i] < ring[m]) m = i;
    }
    final n = ring.length;
    final fwd = ring[(m + 1) % n], back = ring[(m - 1 + n) % n];
    final forward = fwd < back;
    final canon = [
      for (var k = 0; k < n; k++) ring[forward ? (m + k) % n : (m - k + n) % n],
    ];
    final key = 'L${canon[0]}:${canon[1]}';
    final simplified = cache[key] ??= () {
      final s = simplifyLoop([for (final v in canon) pt(v)], tol);
      return s.length < 4 ? [for (final v in canon) pt(v), pt(canon[0])] : s;
    }();
    return forward ? simplified : simplified.reversed.toList();
  }
  final n = ring.length;
  final rotated = [for (var k = 0; k <= n; k++) ring[(firstNode + k) % n]];
  final result = <Point<double>>[];
  var startIdx = 0;
  for (var i = 1; i < rotated.length; i++) {
    if (nodes[rotated[i]] != 1) continue;
    final chain = rotated.sublist(startIdx, i + 1);
    final a = chain.first, b = chain.last;
    final s1 = chain[1], s2 = chain[chain.length - 2];
    final forward = a < b || (a == b && s1 < s2);
    final canon = forward ? chain : chain.reversed.toList();
    final key = '${canon[0]}:${canon[1]}';
    final simplified = cache[key] ??= douglasPeucker([
      for (final v in canon) pt(v),
    ], tol);
    final piece = forward ? simplified : simplified.reversed.toList();
    if (result.isEmpty) {
      result.addAll(piece);
    } else {
      result.addAll(piece.skip(1));
    }
    startIdx = i;
  }
  return result;
}

List<Point<double>> simplifyLoop(List<Point<double>> loop, double tol) {
  // Dibelah di titik pertama dan titik terjauh darinya.
  var far = 0;
  var farD = -1.0;
  for (var i = 0; i < loop.length; i++) {
    final d = loop[i].distanceTo(loop[0]);
    if (d > farD) {
      farD = d;
      far = i;
    }
  }
  final first = douglasPeucker(loop.sublist(0, far + 1), tol);
  final second = douglasPeucker([...loop.sublist(far), loop[0]], tol);
  return [...first, ...second.skip(1)];
}

List<Point<double>> douglasPeucker(List<Point<double>> pts, double tol) {
  if (pts.length < 3) return List.of(pts);
  final keep = List.filled(pts.length, false);
  keep[0] = keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (s, e) = stack.removeLast();
    var maxD = -1.0, idx = -1;
    final a = pts[s], b = pts[e];
    final dx = b.x - a.x, dy = b.y - a.y;
    final len = sqrt(dx * dx + dy * dy);
    for (var i = s + 1; i < e; i++) {
      final p = pts[i];
      final d = len == 0
          ? p.distanceTo(a)
          : ((p.x - a.x) * dy - (p.y - a.y) * dx).abs() / len;
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (idx >= 0 && maxD > tol) {
      keep[idx] = true;
      stack
        ..add((s, idx))
        ..add((idx, e));
    }
  }
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) pts[i],
  ];
}
