import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/campus_map.dart';

/// The map has no HTTP client: every resource ships with the application.
class CampusMapRepository {
  CampusMapRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static final shared = CampusMapRepository();
  static const dataAsset = 'assets/campus_map/map_data.json';

  final AssetBundle _bundle;
  Future<CampusMapData>? _data;
  final Map<String, Future<String>> _maps = {};

  Future<CampusMapData> load() => _data ??= _load();

  Future<CampusMapData> _load() async {
    try {
      final json = jsonDecode(await _bundle.loadString(dataAsset));
      return CampusMapData.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      _data = null;
      rethrow;
    }
  }

  Future<String> loadSvg(CampusMapCampus campus) =>
      _maps.putIfAbsent(campus.id, () async {
        try {
          return await _bundle.loadString(campus.asset);
        } catch (_) {
          _maps.remove(campus.id);
          rethrow;
        }
      });
}
