import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class OsrmService {
  OsrmService._();
  static final instance = OsrmService._();

  static const _baseUrl = 'https://router.project-osrm.org/route/v1/driving';

  Future<List<LatLng>> fetchRoutePolyline(List<LatLng> stops) async {
    if (stops.length < 2) return List<LatLng>.from(stops);

    final coords = stops
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');
    final uri = Uri.parse('$_baseUrl/$coords?overview=full&geometries=geojson');

    final resp = await http.get(uri).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      return List<LatLng>.from(stops);
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      return List<LatLng>.from(stops);
    }

    final geometry = routes.first['geometry'] as Map<String, dynamic>?;
    final coordsList = geometry?['coordinates'] as List<dynamic>?;
    if (coordsList == null || coordsList.isEmpty) {
      return List<LatLng>.from(stops);
    }

    return coordsList
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
  }
}
