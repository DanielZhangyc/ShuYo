import '../../data/services/there_booking_client.dart';

/// Short display labels for known library venues and areas.
///
/// These mappings are presentation-only. When a system name is missing from
/// the tables, keep the name supplied by the booking service unchanged.
abstract final class LibraryBookingNames {
  static const Map<String, String> _venueNames = {
    '校本部图书馆': '本部图书馆',
    '延长智能中心': '智能中心',
    '延长文荟馆': '文荟图书馆',
    '嘉定联合馆': '联合图书馆',
  };

  static const Map<BookingVenue, Map<String, String>> _areaNames = {
    BookingVenue.library: {
      '校本部图书馆自修区 - 二楼东侧': '2楼东侧',
      '校本部图书馆自修区 - 二楼西侧': '2楼西侧',
      '二楼东侧': '2楼东侧',
      '二楼西侧': '2楼西侧',
    },
    BookingVenue.studySpace: {
      '图书馆24小时自习区 - A': 'A区',
      '图书馆24小时自习区 - B': 'B区',
      '图书馆24小时自习区 - C': 'C区',
      '图书馆24小时自习区 - A区': 'A区',
      '图书馆24小时自习区 - B区': 'B区',
      '图书馆24小时自习区 - C区': 'C区',
      'A': 'A区',
      'B': 'B区',
      'C': 'C区',
      'A区': 'A区',
      'B区': 'B区',
      'C区': 'C区',
    },
    BookingVenue.qianweichang: {
      '四楼外圈': '4楼外圈',
      '四楼内圈': '4楼内圈',
      '五楼外圈': '5楼外圈',
      '五楼内圈': '5楼内圈',
    },
    BookingVenue.scienceArt: {
      '科学与艺术中心 - 学生共享创作中心A': '学生共享创作中心A区',
      '科学与艺术中心 - 学生共享创作中心B': '学生共享创作中心B区',
      '科学与艺术中心 - 学生共享创作中心A区': '学生共享创作中心A区',
      '科学与艺术中心 - 学生共享创作中心B区': '学生共享创作中心B区',
      '学生共享创作中心A': '学生共享创作中心A区',
      '学生共享创作中心B': '学生共享创作中心B区',
      '学生共享创作中心A区': '学生共享创作中心A区',
      '学生共享创作中心B区': '学生共享创作中心B区',
      '科学与艺术中心 - 超高清技术与艺术创作空间': '超高清技术与艺术创作空间',
      '科学与艺术中心 - 超高清视景制作共享空间': '超高清视景制作共享空间',
    },
    BookingVenue.yanchang: {
      '智能信息中心智慧共享空间 - B': '智慧共享空间B区',
      '智能信息中心智慧共享空间 - C': '智慧共享空间C区',
      '智能信息中心智慧共享空间 - D': '智慧共享空间D区',
      '智慧共享空间B': '智慧共享空间B区',
      '智慧共享空间C': '智慧共享空间C区',
      '智慧共享空间D': '智慧共享空间D区',
      'B': '智慧共享空间B区',
      'C': '智慧共享空间C区',
      'D': '智慧共享空间D区',
      '智慧共享空间B区': '智慧共享空间B区',
      '智慧共享空间C区': '智慧共享空间C区',
      '智慧共享空间D区': '智慧共享空间D区',
    },
    BookingVenue.jiading: {
      '一楼报刊阅览室': '1楼报刊阅览室',
      '一楼图书阅览室': '1楼图书阅览室',
      '一楼自修室': '1楼自修室',
      '二楼自修区': '2楼自修区',
      '三楼图书阅览室': '3楼图书阅览室',
    },
  };

  static String venue(BookingVenue venue) => venueName(venue.label);

  static String venueName(String systemName) =>
      _venueNames[systemName] ?? systemName;

  static String area(BookingVenue? venue, String systemName) =>
      _areaNames[venue]?[systemName] ?? systemName;
}
