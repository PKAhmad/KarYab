import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Shared with job_finder_screen.dart and ausbildung_screen.dart so a city
// detected via "use my location" on either screen is remembered on both,
// instead of re-asking permission / re-detecting on every visit.
const String kLastKnownCityKey = 'last_known_city';
const String kLastKnownCityAtKey = 'last_known_city_at';
const String kLastKnownPostalCodeKey = 'last_known_postal_code';
const String kLastKnownLatitudeKey = 'last_known_latitude';
const String kLastKnownLongitudeKey = 'last_known_longitude';

Future<String?> loadLastKnownCity() async {
  final prefs = await SharedPreferences.getInstance();
  final city = prefs.getString(kLastKnownCityKey);
  return (city != null && city.isNotEmpty) ? city : null;
}

/// Richer version of [loadLastKnownCity] that also returns the postal code
/// and coordinates persisted alongside the city (when available), so
/// callers like the VHS Kursfinder search can build the precise 'ort'
/// parameter without re-running geolocation/geocoding.
class LastKnownLocation {
  final String city;
  final String? postalCode;
  final double? latitude;
  final double? longitude;

  const LastKnownLocation({
    required this.city,
    this.postalCode,
    this.latitude,
    this.longitude,
  });
}

Future<LastKnownLocation?> loadLastKnownLocation() async {
  final prefs = await SharedPreferences.getInstance();
  final city = prefs.getString(kLastKnownCityKey);
  if (city == null || city.isEmpty) return null;
  return LastKnownLocation(
    city: city,
    postalCode: prefs.getString(kLastKnownPostalCodeKey),
    latitude: prefs.getDouble(kLastKnownLatitudeKey),
    longitude: prefs.getDouble(kLastKnownLongitudeKey),
  );
}

Future<void> saveLastKnownCity(
  String city, {
  String? postalCode,
  double? latitude,
  double? longitude,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kLastKnownCityKey, city);
  await prefs.setString(kLastKnownCityAtKey, DateTime.now().toIso8601String());

  if (postalCode != null && postalCode.isNotEmpty) {
    await prefs.setString(kLastKnownPostalCodeKey, postalCode);
  } else {
    await prefs.remove(kLastKnownPostalCodeKey);
  }

  if (latitude != null && longitude != null) {
    await prefs.setDouble(kLastKnownLatitudeKey, latitude);
    await prefs.setDouble(kLastKnownLongitudeKey, longitude);
  } else {
    await prefs.remove(kLastKnownLatitudeKey);
    await prefs.remove(kLastKnownLongitudeKey);
  }
}

enum LocationLookupError { serviceDisabled, permissionDenied, lookupFailed }

class LocationLookupResult {
  final String? city;
  final String? postalCode;
  final double? latitude;
  final double? longitude;
  final LocationLookupError? error;

  const LocationLookupResult.success(
    this.city, {
    this.postalCode,
    this.latitude,
    this.longitude,
  }) : error = null;

  const LocationLookupResult.failure(this.error)
      : city = null,
        postalCode = null,
        latitude = null,
        longitude = null;
}

/// Detects the user's current city via Geolocator + geocoding.
///
/// Only prompts for permission if it isn't already granted
/// (Geolocator.checkPermission() is checked first, so a previously-granted
/// permission never re-triggers the OS dialog). On success, persists the
/// city via [saveLastKnownCity] so other screens can pre-fill it later.
Future<LocationLookupResult> detectCurrentCity() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return const LocationLookupResult.failure(
        LocationLookupError.serviceDisabled);
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return const LocationLookupResult.failure(
        LocationLookupError.permissionDenied);
  }

  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );
    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    final placemark = placemarks.isNotEmpty ? placemarks.first : null;
    final city = placemark != null
        ? (placemark.locality?.isNotEmpty == true
            ? placemark.locality!
            : placemark.subAdministrativeArea ?? '')
        : '';
    final postalCode = placemark?.postalCode;

    if (city.isEmpty) {
      return const LocationLookupResult.failure(
          LocationLookupError.lookupFailed);
    }

    await saveLastKnownCity(
      city,
      postalCode: postalCode,
      latitude: position.latitude,
      longitude: position.longitude,
    );
    return LocationLookupResult.success(
      city,
      postalCode: postalCode,
      latitude: position.latitude,
      longitude: position.longitude,
    );
  } catch (_) {
    return const LocationLookupResult.failure(
        LocationLookupError.lookupFailed);
  }
}
