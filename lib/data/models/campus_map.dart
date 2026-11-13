import 'dart:math' as math;

class CampusMapPoint {
  const CampusMapPoint(this.x, this.y);

  final double x;
  final double y;

  Map<String, double> toJson() => {'x': x, 'y': y};

  factory CampusMapPoint.fromJson(Map<String, dynamic> json) =>
      CampusMapPoint(_number(json['x']), _number(json['y']));
}

/// Center uses the campus SVG's viewBox coordinates, not longitude/latitude.
/// A zoom of 1 fills the viewport; larger values show a closer view.
class CampusMapView {
  const CampusMapView({required this.center, required this.zoom});

  factory CampusMapView.fromJson(Map<String, dynamic> json) {
    final zoom = _number(json['zoom']);
    if (zoom <= 0) throw const FormatException('Invalid campus map zoom');
    return CampusMapView(
      center: CampusMapPoint.fromJson(json['center'] as Map<String, dynamic>),
      zoom: zoom,
    );
  }

  final CampusMapPoint center;
  final double zoom;

  Map<String, dynamic> toJson() => {'zoom': zoom, 'center': center.toJson()};
}

/// Navigation coordinates in the offline bundle always use GCJ-02.
class CampusMapCoordinate {
  const CampusMapCoordinate(this.longitude, this.latitude);

  final double longitude;
  final double latitude;

  factory CampusMapCoordinate.fromJson(Map<String, dynamic> json) {
    final longitude = _number(json['longitude']);
    final latitude = _number(json['latitude']);
    if (longitude.abs() > 180 || latitude.abs() > 90) {
      throw const FormatException('Invalid campus navigation coordinate');
    }
    return CampusMapCoordinate(longitude, latitude);
  }
}

class CampusMapCampus {
  CampusMapCampus.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        asset = _assetPath(json['asset'], '.svg'),
        viewBox = List<double>.unmodifiable(
          (json['viewBox'] as List).map(_number),
        ),
        transform = Map<String, double>.unmodifiable(
          (json['geoTransform'] as Map<String, dynamic>)
              .map((key, value) => MapEntry(key, _number(value))),
        ),
        metersPerMapUnit = _number(
          (json['metersPerMapUnit'] as Map<String, dynamic>)['x'],
        ),
        initialView = CampusMapView.fromJson(
          json['initialView'] as Map<String, dynamic>,
        ),
        backgroundColor = json['backgroundColor'] as String {
    if (id.isEmpty ||
        name.isEmpty ||
        viewBox.length != 4 ||
        viewBox[2] <= 0 ||
        viewBox[3] <= 0 ||
        metersPerMapUnit <= 0 ||
        !['a', 'b', 'c', 'd', 'e', 'f'].every(transform.containsKey) ||
        !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(backgroundColor)) {
      throw const FormatException('Invalid campus map configuration');
    }
  }

  final String id;
  final String name;
  final String asset;
  final List<double> viewBox;
  final Map<String, double> transform;
  final double metersPerMapUnit;
  final CampusMapView initialView;
  final String backgroundColor;

  int get backgroundArgb =>
      0xff000000 | int.parse(backgroundColor.substring(1), radix: 16);

  CampusMapPoint project(CampusMapCoordinate coordinate) {
    final t = transform;
    return CampusMapPoint(
      t['a']! * coordinate.longitude + t['b']! * coordinate.latitude + t['c']!,
      t['d']! * coordinate.longitude + t['e']! * coordinate.latitude + t['f']!,
    );
  }

  bool contains(CampusMapPoint point) =>
      point.x >= viewBox[0] &&
      point.x <= viewBox[0] + viewBox[2] &&
      point.y >= viewBox[1] &&
      point.y <= viewBox[1] + viewBox[3];
}

class CampusMapFact {
  const CampusMapFact(this.label, this.value);

  final String label;
  final String value;
}

class CampusMapPlace {
  CampusMapPlace.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        campusId = json['campusId'] as String,
        name = json['name'] as String,
        kind = json['kind'] as String,
        address = json['address'] as String,
        description = json['description'] as String,
        aliases = _strings(json['aliases']),
        featureIds = _strings(json['featureIds']),
        facts = List<CampusMapFact>.unmodifiable(
          (json['facts'] as List).map((value) {
            final fact = value as Map<String, dynamic>;
            return CampusMapFact(
                fact['label'] as String, fact['value'] as String);
          }),
        ),
        point = json['point'] == null
            ? null
            : CampusMapPoint.fromJson(json['point'] as Map<String, dynamic>),
        navigation = json['navigation'] == null
            ? null
            : CampusMapCoordinate.fromJson(
                json['navigation'] as Map<String, dynamic>,
              ) {
    if (id.isEmpty || campusId.isEmpty || name.isEmpty) {
      throw const FormatException('Invalid campus map place');
    }
  }

  final String id;
  final String campusId;
  final String name;
  final String kind;
  final String address;
  final String description;
  final List<String> aliases;
  final List<String> featureIds;
  final List<CampusMapFact> facts;
  final CampusMapPoint? point;
  final CampusMapCoordinate? navigation;

  Map<String, dynamic> toCanvasJson() => {
        'id': id,
        'featureIds': featureIds,
        if (point != null) 'point': point!.toJson(),
      };
}

class CampusMapData {
  CampusMapData.fromJson(Map<String, dynamic> json)
      : version = json['version'] as String,
        publishedAt = DateTime.parse(json['publishedAt'] as String),
        campuses = List<CampusMapCampus>.unmodifiable(
          (json['campuses'] as List).map(
            (value) => CampusMapCampus.fromJson(value as Map<String, dynamic>),
          ),
        ),
        places = List<CampusMapPlace>.unmodifiable(
          (json['places'] as List).map(
            (value) => CampusMapPlace.fromJson(value as Map<String, dynamic>),
          ),
        ) {
    if (json['schemaVersion'] != 1 || campuses.isEmpty || version.isEmpty) {
      throw const FormatException('Unsupported offline campus map');
    }
    campusById = Map.unmodifiable({for (final c in campuses) c.id: c});
    placeById = Map.unmodifiable({for (final p in places) p.id: p});
    if (campusById.length != campuses.length ||
        placeById.length != places.length ||
        places.any((place) => !campusById.containsKey(place.campusId))) {
      throw const FormatException('Invalid campus map references');
    }
  }

  final String version;
  final DateTime publishedAt;
  final List<CampusMapCampus> campuses;
  final List<CampusMapPlace> places;
  late final Map<String, CampusMapCampus> campusById;
  late final Map<String, CampusMapPlace> placeById;

  CampusMapCampus initialCampus(String preferredName) => campuses.firstWhere(
        (campus) => campus.name == preferredName || campus.id == preferredName,
        orElse: () => campuses.first,
      );

  CampusMapCampus? campusAt(CampusMapCoordinate coordinate) {
    for (final campus in campuses) {
      if (campus.contains(campus.project(coordinate))) return campus;
    }
    return null;
  }

  List<CampusMapPlace> search(String query, {String? preferredCampusId}) {
    final keyword = normalizeCampusMapSearch(query);
    if (keyword.isEmpty) return const [];
    final matches = <(CampusMapPlace, int)>[];
    for (final place in places) {
      final name = normalizeCampusMapSearch(place.name);
      final aliases = place.aliases.map(normalizeCampusMapSearch);
      final int score;
      if (name == keyword) {
        score = 0;
      } else if (aliases.contains(keyword)) {
        score = 1;
      } else if (name.startsWith(keyword)) {
        score = 2;
      } else if (name.contains(keyword)) {
        score = 3;
      } else if (aliases.any((alias) => alias.contains(keyword))) {
        score = 4;
      } else if (normalizeCampusMapSearch(place.kind).contains(keyword)) {
        score = 5;
      } else if (normalizeCampusMapSearch([
        place.description,
        for (final fact in place.facts) fact.value,
      ].join(' '))
          .contains(keyword)) {
        score = 6;
      } else if (normalizeCampusMapSearch(
        '${campusById[place.campusId]!.name}${place.address}',
      ).contains(keyword)) {
        score = 7;
      } else {
        continue;
      }
      matches.add((place, score));
    }
    matches.sort((left, right) {
      final score = left.$2.compareTo(right.$2);
      if (score != 0) return score;
      final campus = (left.$1.campusId == preferredCampusId ? 0 : 1)
          .compareTo(right.$1.campusId == preferredCampusId ? 0 : 1);
      return campus != 0 ? campus : left.$1.name.compareTo(right.$1.name);
    });
    return List.unmodifiable(matches.map((match) => match.$1));
  }
}

String normalizeCampusMapSearch(String value) => String.fromCharCodes(
      value.runes.map(
          (rune) => rune >= 0xff01 && rune <= 0xff5e ? rune - 0xfee0 : rune),
    ).toLowerCase().replaceAll(RegExp(r'[\s\u3000（）()]+'), '');

/// Same WGS-84 -> GCJ-02 conversion used by SHUMap's shared/geo-transform.mjs.
/// Device coordinates must be converted once before applying the SVG affine map.
CampusMapCoordinate campusMapWgs84ToGcj02(double longitude, double latitude) {
  if (!longitude.isFinite ||
      !latitude.isFinite ||
      longitude.abs() > 180 ||
      latitude.abs() > 90) {
    throw const FormatException('Invalid device location');
  }
  if (longitude < 72.004 ||
      longitude > 137.8347 ||
      latitude < 0.8293 ||
      latitude > 55.8271) {
    return CampusMapCoordinate(longitude, latitude);
  }
  const a = 6378245.0;
  const ee = 0.006693421622965943;
  final x = longitude - 105;
  final y = latitude - 35;
  var dLat = -100 +
      2 * x +
      3 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * math.sqrt(x.abs());
  var dLng =
      300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
  final common =
      (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) * 2 / 3;
  dLat += common +
      (20 * math.sin(y * math.pi) + 40 * math.sin(y / 3 * math.pi)) * 2 / 3 +
      (160 * math.sin(y / 12 * math.pi) + 320 * math.sin(y * math.pi / 30)) *
          2 /
          3;
  dLng += common +
      (20 * math.sin(x * math.pi) + 40 * math.sin(x / 3 * math.pi)) * 2 / 3 +
      (150 * math.sin(x / 12 * math.pi) + 300 * math.sin(x / 30 * math.pi)) *
          2 /
          3;
  final radLat = latitude / 180 * math.pi;
  final magic = 1 - ee * math.pow(math.sin(radLat), 2);
  final sqrtMagic = math.sqrt(magic);
  dLat = dLat * 180 / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi);
  dLng = dLng * 180 / (a / sqrtMagic * math.cos(radLat) * math.pi);
  return CampusMapCoordinate(longitude + dLng, latitude + dLat);
}

double _number(dynamic value) {
  if (value is! num || !value.isFinite) {
    throw const FormatException('Expected a finite campus map number');
  }
  return value.toDouble();
}

List<String> _strings(dynamic value) =>
    List<String>.unmodifiable((value as List).cast<String>());

String _assetPath(dynamic value, [String? extension]) {
  if (value is! String ||
      !value.startsWith('assets/campus_map/') ||
      value.contains('..') ||
      value.contains('://') ||
      (extension != null && !value.endsWith(extension))) {
    throw const FormatException('Invalid offline map asset path');
  }
  return value;
}
