import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:x9_core/x9_core.dart';

/// Location for the sign-up form. Returns null when no fix could be read; throws an [Exception] with a clear,
/// readable message when location is off or the permission is denied.
Future<({double lat, double lng})?> locateForSignup() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception('Location is switched off. Turn on location in your phone settings and try again.');
  }
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.deniedForever) {
    throw Exception('Location permission is blocked. Open phone Settings > Apps > X9 > Permissions, allow Location, then try again.');
  }
  if (p == LocationPermission.denied || p == LocationPermission.unableToDetermine) {
    throw Exception('Location permission was denied. X9 needs your location to create your account. Tap "Set location" and choose Allow.');
  }
  Position? pos;
  try {
    pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
  } catch (_) {
    pos = await Geolocator.getLastKnownPosition();
  }
  if (pos == null) return null;
  return (lat: pos.latitude, lng: pos.longitude);
}

/// v6.10: the GPS fix as a home address (house / street, area, city, state, pin code), like a delivery app.
Future<SignupPlace?> reverseGeocodeForSignup(double lat, double lng) async {
  final marks = await geo.placemarkFromCoordinates(lat, lng);
  if (marks.isEmpty) return null;
  final m = marks.first;
  String t(String? v) => (v ?? '').trim();
  final city = t(m.locality).isNotEmpty ? t(m.locality) : t(m.subAdministrativeArea);
  final parts = <String>[];
  for (final v in [t(m.name), t(m.street), t(m.subLocality), city, t(m.administrativeArea)]) {
    if (v.isEmpty || v == '+' || parts.any((p) => p.toLowerCase().contains(v.toLowerCase()))) continue;
    parts.add(v);
  }
  final pin = t(m.postalCode);
  return (address: parts.join(', '), pincode: RegExp(r'^[1-9]\d{5}$').hasMatch(pin) ? pin : '', city: city);
}
