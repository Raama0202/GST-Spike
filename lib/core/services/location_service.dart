import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationIssue { serviceDisabled, denied, deniedForever, unavailable }

/// Outcome of a capture: either coordinates or the reason there are none.
class LocationCapture {
  const LocationCapture.success(double this.latitude, double this.longitude)
      : issue = null;

  const LocationCapture.failed(LocationIssue this.issue)
      : latitude = null,
        longitude = null;

  final double? latitude;
  final double? longitude;
  final LocationIssue? issue;

  bool get ok => issue == null;

  String get message => switch (issue) {
        null => 'Location captured',
        LocationIssue.serviceDisabled =>
          'Location is turned off. Turn it on to submit bills.',
        LocationIssue.denied =>
          'Location permission was denied. Your company requires it to submit bills.',
        LocationIssue.deniedForever =>
          'Location permission is blocked. Allow it in Settings to submit bills.',
        LocationIssue.unavailable =>
          'Could not get your location. Move to an open area and retry.',
      };
}

/// One-shot location for companies that require GPS on every upload.
class LocationService {
  static const _timeLimit = Duration(seconds: 15);

  Future<LocationCapture> capture() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationCapture.failed(LocationIssue.serviceDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationCapture.failed(LocationIssue.deniedForever);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        return const LocationCapture.failed(LocationIssue.denied);
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: _timeLimit,
          ),
        );
        return LocationCapture.success(position.latitude, position.longitude);
      } on TimeoutException {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return LocationCapture.success(last.latitude, last.longitude);
        }
        return const LocationCapture.failed(LocationIssue.unavailable);
      }
    } catch (_) {
      return const LocationCapture.failed(LocationIssue.unavailable);
    }
  }

  Future<void> openSettings(LocationIssue issue) async {
    if (issue == LocationIssue.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
