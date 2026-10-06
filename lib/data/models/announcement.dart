import 'common.dart';
import 'announcement_source.dart';

enum AnnouncementContentType {
  text,
  image,
  link,
  table,
}

class AnnouncementContentBlock {
  const AnnouncementContentBlock.text(this.value)
      : type = AnnouncementContentType.text,
        alt = '',
        label = '',
        rows = const [];

  const AnnouncementContentBlock.image(
    this.value, {
    this.alt = '',
  })  : type = AnnouncementContentType.image,
        label = '',
        rows = const [];

  const AnnouncementContentBlock.link(this.value, {required this.label})
      : type = AnnouncementContentType.link,
        alt = '',
        rows = const [];

  const AnnouncementContentBlock.table(this.rows)
      : type = AnnouncementContentType.table,
        value = '',
        alt = '',
        label = '';

  final AnnouncementContentType type;
  final String value;
  final String alt;
  final String label;
  final List<List<String>> rows;

  bool get isText => type == AnnouncementContentType.text;
  bool get isImage => type == AnnouncementContentType.image;
  bool get isLink => type == AnnouncementContentType.link;
  bool get isTable => type == AnnouncementContentType.table;

  JsonMap toJson() {
    return {
      'type': type.name,
      'value': value,
      'alt': alt,
      'label': label,
      'rows': rows,
    };
  }

  factory AnnouncementContentBlock.fromJson(JsonMap json) {
    final type = stringValue(json['type']);
    final value = stringValue(json['value']);
    if (type == AnnouncementContentType.image.name) {
      return AnnouncementContentBlock.image(
        value,
        alt: stringValue(json['alt']),
      );
    }
    if (type == AnnouncementContentType.link.name) {
      return AnnouncementContentBlock.link(
        value,
        label: stringValue(json['label']),
      );
    }
    if (type == AnnouncementContentType.table.name) {
      final rows = (json['rows'] as List? ?? const [])
          .whereType<List>()
          .map((row) => row.map((cell) => cell.toString()).toList())
          .toList();
      return AnnouncementContentBlock.table(rows);
    }
    return AnnouncementContentBlock.text(value);
  }
}

class AnnouncementListItem {
  const AnnouncementListItem({
    required this.title,
    required this.url,
    this.summary = '',
    this.dateText = '',
    this.publishedAt,
    this.sourceId = AnnouncementSource.officialId,
    this.column = '',
  });

  final String title;
  final String url;
  final String summary;
  final String dateText;
  final DateTime? publishedAt;
  final String sourceId;
  final String column;

  JsonMap toJson() {
    return {
      'title': title,
      'url': url,
      'summary': summary,
      'dateText': dateText,
      'publishedAt': publishedAt?.toIso8601String(),
      'sourceId': sourceId,
      'column': column,
    };
  }

  factory AnnouncementListItem.fromJson(JsonMap json) {
    return AnnouncementListItem(
      title: stringValue(json['title']),
      url: stringValue(json['url']),
      summary: stringValue(json['summary']),
      dateText: stringValue(json['dateText']),
      publishedAt: dateValue(json['publishedAt']),
      sourceId: stringValue(json['sourceId']).isEmpty
          ? AnnouncementSource.officialId
          : stringValue(json['sourceId']),
      column: stringValue(json['column']),
    );
  }
}

class AnnouncementDetail {
  const AnnouncementDetail({
    required this.title,
    required this.url,
    required this.blocks,
    this.dateText = '',
    this.publishedAt,
    this.author = '',
    this.department = '',
  });

  final String title;
  final String url;
  final List<AnnouncementContentBlock> blocks;
  final String dateText;
  final DateTime? publishedAt;
  final String author;
  final String department;

  bool get hasContent => blocks.isNotEmpty;
}
