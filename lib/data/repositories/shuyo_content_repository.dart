import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/client_backend_constants.dart';

enum ShuyoContentKind { announcements, tips }

extension ShuyoContentKindLabel on ShuyoContentKind {
  String get label => this == ShuyoContentKind.announcements ? '系统公告' : '使用提示';
  String get path =>
      this == ShuyoContentKind.announcements ? 'announcements' : 'tips';
}

class ShuyoContentItem {
  const ShuyoContentItem({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ShuyoContentItem.fromJson(Map<String, dynamic> json) =>
      ShuyoContentItem(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };
}

class ShuyoContentLoad {
  const ShuyoContentLoad(this.items, {this.fromCache = false, this.message});

  final List<ShuyoContentItem> items;
  final bool fromCache;
  final String? message;
}

class ShuyoContentException implements Exception {
  const ShuyoContentException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ShuyoContentRepository {
  ShuyoContentRepository({
    http.Client? client,
    Future<SharedPreferences> Function()? preferencesLoader,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _baseUrl = baseUrl ?? ClientBackendConstants.baseUrl;

  final http.Client _client;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final String _baseUrl;

  Uri get baseUri => Uri.parse(_baseUrl);

  Future<ShuyoContentLoad> load(ShuyoContentKind kind) async {
    final key = 'shuyo.content.${kind.path}.v1';
    try {
      final response = await _client
          .get(baseUri.resolve('/api/v1/${kind.path}'), headers: {
        'accept': 'application/json'
      }).timeout(const Duration(seconds: 12));
      if (response.statusCode == 404) {
        throw const ShuyoContentException('当前服务器暂未提供此列表。');
      }
      if (response.statusCode != 200) {
        throw const ShuyoContentException('加载失败，请稍后重试。');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map ||
          decoded['success'] != true ||
          decoded['data'] is! List) {
        throw const ShuyoContentException('列表数据格式有误。');
      }
      final items = (decoded['data'] as List)
          .whereType<Map>()
          .map((raw) =>
              ShuyoContentItem.fromJson(Map<String, dynamic>.from(raw)))
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList(growable: false);
      try {
        final prefs = await _preferencesLoader();
        await prefs.setString(
            key, jsonEncode(items.map((item) => item.toJson()).toList()));
      } on Object {
        // A storage failure must not hide content already received from the server.
      }
      return ShuyoContentLoad(items);
    } on Object catch (error) {
      String? cached;
      try {
        cached = (await _preferencesLoader()).getString(key);
      } on Object {
        // Continue with the request failure when local storage is unavailable.
      }
      if (cached != null) {
        try {
          final raw = jsonDecode(cached);
          if (raw is List) {
            return ShuyoContentLoad(
              raw
                  .whereType<Map>()
                  .map((value) => ShuyoContentItem.fromJson(
                      Map<String, dynamic>.from(value)))
                  .toList(growable: false),
              fromCache: true,
              message: '当前无法更新，正在显示已保存的内容。',
            );
          }
        } on Object {
          // Ignore an invalid cache and show the request failure.
        }
      }
      if (error is ShuyoContentException) rethrow;
      throw const ShuyoContentException('当前无法加载，请检查网络后重试。');
    }
  }
}
