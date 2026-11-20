import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

// Batas desa dan zona kerentanan longsor ditelusuri dari gambar peta Kajian
// Pemetaan Bencana Desa Lumeneng 2024 (tool/peta_dari_kajian.dart). Bila tim
// pemetaan memberi shapefile asli, ekspor ke GeoJSON WGS84 dengan properti
// `kelas` yang sama lalu timpa kedua berkas ini.
const villageBoundaryAsset = 'assets/peta/batas_desa.geojson';
const landslideZonesAsset = 'assets/peta/zona_longsor.geojson';

/// Area pantau tiap alat EWS, satu Polygon per alat dengan properti `id`
/// sama dengan id alat. Selama masih berisi `"contoh": true` di tingkat atas,
/// legenda menandainya sebagai contoh.
const monitoringAreasAsset = 'assets/peta/area_ews.geojson';

/// Kelas di legenda Peta Rawan Longsor kajian, urut dari yang paling aman.
enum LandslideZone {
  aman('aman', 'Aman', Color(0xFF5FC0E8)),
  agakRawan('agak_rawan', 'Agak rawan', Color(0xFFFACD19)),
  rawan('rawan', 'Rawan', Color(0xFFF42612)),
  sangatRawan('sangat_rawan', 'Sangat rawan', Color(0xFF8C0408));

  const LandslideZone(this.code, this.label, this.color);

  /// Nilai properti `kelas` di GeoJSON.
  final String code;
  final String label;

  /// Warna legenda kajian, supaya peta di aplikasi terbaca sama dengan
  /// peta cetaknya.
  final Color color;
}

class ZoneArea {
  const ZoneArea(this.zone, this.outline, this.holes);

  final LandslideZone zone;
  final List<LatLng> outline;
  final List<List<LatLng>> holes;
}

class VillageMap {
  const VillageMap({
    required this.boundary,
    required this.zones,
    this.monitoringAreas = const {},
    this.monitoringAreasAreSamples = false,
  });

  final List<LatLng> boundary;

  /// Urut dari [LandslideZone.aman] ke [LandslideZone.sangatRawan], jadi garis
  /// zona yang lebih rawan tergambar paling atas.
  final List<ZoneArea> zones;

  /// Kuncinya id alat, mis. `EWS-01`.
  final Map<String, List<LatLng>> monitoringAreas;
  final bool monitoringAreasAreSamples;

  factory VillageMap.fromGeoJson({
    required String boundary,
    required String zones,
    String? monitoringAreas,
  }) {
    final boundaryGeometry =
        ((jsonDecode(boundary) as Map)['features'] as List).first['geometry']
            as Map;
    final areas = <ZoneArea>[];
    for (final feature in (jsonDecode(zones) as Map)['features'] as List) {
      final code = (feature['properties'] as Map)['kelas'];
      final zone = LandslideZone.values.where((z) => z.code == code).first;
      for (final polygon in _polygons(feature['geometry'] as Map)) {
        areas.add(ZoneArea(zone, polygon.first, polygon.sublist(1)));
      }
    }
    areas.sort((a, b) => a.zone.index.compareTo(b.zone.index));

    final monitoring = monitoringAreas == null
        ? const <String, dynamic>{}
        : jsonDecode(monitoringAreas) as Map<String, dynamic>;
    return VillageMap(
      boundary: _polygons(boundaryGeometry).first.first,
      zones: areas,
      monitoringAreas: {
        for (final feature in monitoring['features'] as List? ?? const [])
          (feature['properties'] as Map)['id'] as String: _polygons(
            feature['geometry'] as Map,
          ).first.first,
      },
      monitoringAreasAreSamples: monitoring['contoh'] == true,
    );
  }
}

/// Polygon dan MultiPolygon jadi daftar poligon; tiap poligon berisi cincin
/// luar lalu lubang-lubangnya.
List<List<List<LatLng>>> _polygons(Map geometry) {
  List<LatLng> ring(List coords) => [
    for (final point in coords)
      LatLng((point[1] as num).toDouble(), (point[0] as num).toDouble()),
  ];
  List<List<LatLng>> polygon(List rings) => [
    for (final r in rings) ring(r as List),
  ];

  final coordinates = geometry['coordinates'] as List;
  return switch (geometry['type']) {
    'Polygon' => [polygon(coordinates)],
    'MultiPolygon' => [for (final p in coordinates) polygon(p as List)],
    final type => throw FormatException('Geometri $type tidak didukung'),
  };
}

Future<VillageMap>? _loaded;

/// Dibaca sekali per jalannya aplikasi.
Future<VillageMap> loadVillageMap([AssetBundle? bundle]) {
  final assets = bundle ?? rootBundle;
  // Bukan loadString: berkas di atas 50 KB dibacanya lewat compute(), yang
  // tidak ikut jam palsu di tes widget. Untuk ±140 KB membaca langsung cukup
  // cepat.
  Future<String> read(String key) async =>
      utf8.decode((await assets.load(key)).buffer.asUint8List());
  return _loaded ??= () async {
    return VillageMap.fromGeoJson(
      boundary: await read(villageBoundaryAsset),
      zones: await read(landslideZonesAsset),
      monitoringAreas: await read(monitoringAreasAsset),
    );
  }();
}
