import 'package:geolocator/geolocator.dart';

typedef PhoneFix = ({double latitude, double longitude, double accuracy});

enum LocationProblem { serviceOff, denied, notFound }

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.problem);

  final LocationProblem problem;
}

/// Posisi HP sekarang, akurasinya dalam meter. Di dalam rumah GPS sering
/// belum dapat sinyal, jadi bila waktunya habis dipakai lokasi terakhir yang
/// diketahui HP. Gagal dilempar sebagai [LocationUnavailable].
Future<PhoneFix> findPhoneLocation({
  Duration timeLimit = const Duration(seconds: 30),
}) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationUnavailable(LocationProblem.serviceOff);
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const LocationUnavailable(LocationProblem.denied);
  }

  Position? position;
  try {
    position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      ),
    );
  } catch (_) {
    position = await Geolocator.getLastKnownPosition();
  }
  if (position == null) {
    throw const LocationUnavailable(LocationProblem.notFound);
  }
  return (
    latitude: position.latitude,
    longitude: position.longitude,
    accuracy: position.accuracy,
  );
}
