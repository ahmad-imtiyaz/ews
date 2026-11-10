import 'dart:io';

import 'package:ews/data/sample_data.dart';
import 'package:ews/data/village_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

bool _inside(LatLng p, List<LatLng> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
        p.longitude <
            (b.longitude - a.longitude) *
                    (p.latitude - a.latitude) /
                    (b.latitude - a.latitude) +
                a.longitude) {
      inside = !inside;
    }
  }
  return inside;
}

void main() {
  late VillageMap map;

  setUpAll(() {
    map = VillageMap.fromGeoJson(
      boundary: File(villageBoundaryAsset).readAsStringSync(),
      zones: File(landslideZonesAsset).readAsStringSync(),
      monitoringAreas: File(monitoringAreasAsset).readAsStringSync(),
    );
  });

  test('keempat kelas legenda kajian ada', () {
    expect(map.zones.map((z) => z.zone).toSet(), LandslideZone.values.toSet());
  });

  test('zona urut dari aman ke sangat rawan', () {
    final order = [for (final z in map.zones) z.zone.index];
    expect(order, [...order]..sort());
  });

  test('batas desa di grid peta kajian, bukan koordinat teks yang salah', () {
    for (final p in map.boundary) {
      expect(p.longitude, inInclusiveRange(109.56, 109.61));
      expect(p.latitude, inInclusiveRange(-7.22, -7.15));
    }
  });

  test('titik contoh EWS dan laporan ada di dalam desa', () {
    for (final p in mapFocusPoints) {
      expect(_inside(p, map.boundary), isTrue, reason: '$p');
    }
  });

  test('tiap alat punya area pantau yang memuat titiknya', () {
    // Area dari tim lapangan, bukan oval contoh lagi.
    expect(map.monitoringAreasAreSamples, isFalse);
    for (final sensor in waspadaData.sensors) {
      final area = map.monitoringAreas[sensor.id];
      expect(area, isNotNull, reason: sensor.id);
      expect(_inside(sensor.position, area!), isTrue, reason: sensor.id);
    }
  });
}
