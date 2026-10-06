import 'dart:convert';
import 'dart:async';
import 'dart:collection';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/announcement.dart';
import '../models/announcement_source.dart';
import '../models/common.dart';
import '../services/announcement_api_client.dart';
import '../services/client_settings_service.dart';

class AnnouncementHomeSummary {
  const AnnouncementHomeSummary(this.text);

  final String text;
}

class AnnouncementRepository {
  AnnouncementRepository({
    AnnouncementApiClient? apiClient,
    Future<SharedPreferences> Function()? preferencesLoader,
    this.autoRefreshInterval = defaultAutoRefreshInterval,
  })  : _apiClient = apiClient ?? AnnouncementApiClient(),
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const defaultAutoRefreshInterval = Duration(hours: 12);
  static const _listCacheKey = 'announcements.list.cache';
  static const _lastRefreshKey = 'announcements.lastRefreshAt';
  static const _cacheVersionKey = 'announcements.cacheVersion';
  static const _defaultSourceKey =
      ClientSettingsService.defaultAnnouncementSourceKey;
  static const _favoritesKey = 'announcements.favoriteSources';
  static const _cacheVersion = 4;

  final AnnouncementApiClient _apiClient;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final Duration autoRefreshInterval;

  final Map<String, List<AnnouncementListItem>> _memoryLists = {};
  final Map<String, String?> _previews = {};
  final Map<String, Future<String?>> _pendingPreviews = {};
  final Map<String, AnnouncementDetail> _recentDetails = {};
  final Map<String, Future<AnnouncementDetail>> _pendingDetails = {};
  final Queue<({AnnouncementListItem item, Completer<String?> completer})>
      _previewQueue = Queue();
  int _activePreviewRequests = 0;

  /// Detail requests for list previews are limited so scrolling a long list
  /// does not open a connection for every announcement at once.
  Future<String?> loadPreview(AnnouncementListItem item) {
    if (item.summary.isNotEmpty) return Future.value(item.summary);
    final key = '${item.sourceId}|${item.url}';
    if (_previews.containsKey(key)) return Future.value(_previews[key]);
    final pending = _pendingPreviews[key];
    if (pending != null) return pending;
    final completer = Completer<String?>();
    _pendingPreviews[key] = completer.future;
    _previewQueue.add((item: item, completer: completer));
    _pumpPreviewQueue();
    return completer.future;
  }

  void _pumpPreviewQueue() {
    while (_activePreviewRequests < 3 && _previewQueue.isNotEmpty) {
      final request = _previewQueue.removeFirst();
      _activePreviewRequests++;
      unawaited(_loadQueuedPreview(request));
    }
  }

  Future<void> _loadQueuedPreview(
    ({AnnouncementListItem item, Completer<String?> completer}) request,
  ) async {
    final item = request.item;
    final key = '${item.sourceId}|${item.url}';
    try {
      final detail = await fetchDetail(item);
      final text = detail.blocks
          .where((block) => block.isText)
          .map((block) => block.value.trim())
          .where((value) => value.isNotEmpty && value != detail.title)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final preview = text.isEmpty
          ? detail.blocks.any((block) =>
                  block.isLink &&
                  Uri.tryParse(block.value)
                          ?.path
                          .toLowerCase()
                          .endsWith('.pdf') ==
                      true)
              ? '[PDF文件]'
              : detail.blocks.any((block) => block.isImage)
                  ? '[图片]'
                  : detail.blocks.any((block) => block.isTable)
                      ? '[表格]'
                      : null
          : text.length > 110
              ? '${text.substring(0, 110)}…'
              : text;
      _previews[key] = preview;
      request.completer.complete(preview);
    } on Object {
      // A failed detail request is retried if the item is built again later.
      request.completer.complete(null);
    } finally {
      _pendingPreviews.remove(key);
      _activePreviewRequests--;
      _pumpPreviewQueue();
    }
  }

  Future<AnnouncementSource> defaultSource() async {
    final prefs = await _preferencesLoader();
    return AnnouncementSource.byId(prefs.getString(_defaultSourceKey));
  }

  Future<void> setDefaultSource(AnnouncementSource source) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(_defaultSourceKey, source.id);
  }

  Future<Set<String>> favoriteSourceIds() async {
    final prefs = await _preferencesLoader();
    final known = AnnouncementSource.all.map((source) => source.id).toSet();
    return (prefs.getStringList(_favoritesKey) ?? const <String>[])
        .where(known.contains)
        .toSet();
  }

  Future<Set<String>> toggleFavoriteSource(AnnouncementSource source) async {
    final prefs = await _preferencesLoader();
    final ids = await favoriteSourceIds();
    if (!ids.add(source.id)) ids.remove(source.id);
    await prefs.setStringList(_favoritesKey, ids.toList());
    return ids;
  }

  Future<List<AnnouncementListItem>> loadCachedAnnouncements({
    AnnouncementSource? source,
  }) async {
    final selected = source ?? await defaultSource();
    if (_memoryLists.containsKey(selected.id)) {
      return _memoryLists[selected.id]!;
    }
    final prefs = await _preferencesLoader();
    final raw = prefs.getString('$_listCacheKey.${selected.id}') ??
        (selected == AnnouncementSource.official
            ? prefs.getString(_listCacheKey)
            : null);
    if (raw == null || raw.isEmpty) {
      return const <AnnouncementListItem>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <AnnouncementListItem>[];
    }
    final today = DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day)
        .subtract(AnnouncementApiClient.maxAge);
    final items = decoded
        .whereType<JsonMap>()
        .map(AnnouncementListItem.fromJson)
        .where((item) =>
            item.publishedAt == null || !item.publishedAt!.isBefore(cutoff))
        .toList();
    items.sort((a, b) {
      final left = a.publishedAt;
      final right = b.publishedAt;
      if (left == null) return right == null ? 0 : 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
    final recent =
        items.take(AnnouncementApiClient.maxItems).toList(growable: false);
    _memoryLists[selected.id] = recent;
    return recent;
  }

  Future<List<AnnouncementListItem>> fetchAnnouncements({
    AnnouncementSource? source,
    bool forceRefresh = false,
  }) async {
    final selected = source ?? await defaultSource();
    if (!forceRefresh && !await _shouldAutoRefresh(selected)) {
      return loadCachedAnnouncements(source: selected);
    }
    try {
      final items = await _apiClient.fetchAnnouncements(source: selected);
      await _saveList(selected, items);
      return items;
    } on Object {
      final cached = await loadCachedAnnouncements(source: selected);
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  Future<AnnouncementDetail> fetchDetail(AnnouncementListItem item) {
    final key = '${item.sourceId}|${item.url}';
    final cached = _recentDetails[key];
    if (cached != null) return Future.value(cached);
    final pending = _pendingDetails[key];
    if (pending != null) return pending;
    Future<AnnouncementDetail> load() async {
      try {
        final detail = await _apiClient.fetchDetail(item);
        _recentDetails.remove(key);
        _recentDetails[key] = detail;
        if (_recentDetails.length > 12) {
          _recentDetails.remove(_recentDetails.keys.first);
        }
        return detail;
      } finally {
        _pendingDetails.remove(key);
      }
    }

    final task = load();
    _pendingDetails[key] = task;
    return task;
  }

  Future<AnnouncementHomeSummary> homeSummary() async {
    final source = await defaultSource();
    final cached = await loadCachedAnnouncements(source: source);
    if (cached.isNotEmpty) {
      return AnnouncementHomeSummary(source == AnnouncementSource.official
          ? cached.first.title
          : '${source.name} · ${cached.first.title}');
    }
    return AnnouncementHomeSummary('点击查看${source.name}公告');
  }

  Future<bool> _shouldAutoRefresh(AnnouncementSource source) async {
    final prefs = await _preferencesLoader();
    if (prefs.getInt('$_cacheVersionKey.${source.id}') != _cacheVersion) {
      return true;
    }
    final raw = prefs.getString('$_lastRefreshKey.${source.id}');
    final lastRefresh = raw == null ? null : DateTime.tryParse(raw);
    if (lastRefresh == null) {
      return true;
    }
    return DateTime.now().difference(lastRefresh) >= autoRefreshInterval;
  }

  Future<void> _saveList(
    AnnouncementSource source,
    List<AnnouncementListItem> items,
  ) async {
    _memoryLists[source.id] = items;
    final prefs = await _preferencesLoader();
    await prefs.setString(
      '$_listCacheKey.${source.id}',
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(
      '$_lastRefreshKey.${source.id}',
      DateTime.now().toIso8601String(),
    );
    await prefs.setInt('$_cacheVersionKey.${source.id}', _cacheVersion);
  }
}
