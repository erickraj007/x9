import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:x9_core/x9_core.dart';

/// Phone location for the home feed + the live-user heartbeat (POST /app/location every 5 min in foreground).
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  double? lat;
  double? lng;
  String? city;
  String? state;
  bool denied = false;
  bool _explained = false;
  Timer? _heartbeat;

  bool get hasFix => lat != null && lng != null;

  /// Gets a GPS fix and the city/state. With [context] the person is first told why location is needed.
  /// Returns true when a fix was obtained.
  Future<bool> locate(BuildContext? context, {bool ask = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        denied = true;
        return false;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied && ask) {
        if (context != null && context.mounted && !_explained) {
          _explained = true;
          final allow = await _explain(context);
          if (!allow) {
            denied = true;
            return false;
          }
        }
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever || p == LocationPermission.unableToDetermine) {
        denied = true;
        return false;
      }
      denied = false;
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return false;
      lat = pos.latitude;
      lng = pos.longitude;
      await _geocode(pos.latitude, pos.longitude);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _geocode(double la, double ln) async {
    try {
      final marks = await geo.placemarkFromCoordinates(la, ln);
      if (marks.isEmpty) return;
      final m = marks.first;
      final c = (m.locality ?? '').isNotEmpty ? m.locality : m.subAdministrativeArea;
      if (c != null && c.isNotEmpty) city = c;
      if ((m.administrativeArea ?? '').isNotEmpty) state = m.administrativeArea;
    } catch (_) {}
  }

  Map<String, dynamic> get query => {
        if (lat != null) 'lat': lat!.toStringAsFixed(6),
        if (lng != null) 'lng': lng!.toStringAsFixed(6),
        if (city != null) 'city': city,
        if (state != null) 'state': state,
      };

  /// Live-user heartbeat. Errors are ignored.
  Future<void> send() async {
    if (!hasFix || !SessionStore.instance.signedIn) return;
    try {
      await Api.instance.post('/app/location', {
        'lat': lat,
        'lng': lng,
        if (city != null) 'city': city,
        if (state != null) 'state': state,
      });
    } catch (_) {}
  }

  void startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (!denied) await locate(null, ask: false);
      await send();
    });
  }

  void stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<bool> _explain(BuildContext context) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(gradient: X9Colors.heroGradient, shape: BoxShape.circle),
              child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 38),
            ),
            const SizedBox(height: 16),
            Text('Find offers near you', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'X9 uses your location to show shops, offers and banners in your city and to give you directions. '
              'Your location is used only while the app is open.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.x9.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(c, true),
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('Allow location'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          ]),
        ),
      ),
    );
    return ok == true;
  }
}
