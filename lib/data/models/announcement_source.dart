enum AnnouncementListFormat {
  shuHome,
  onlyList,
  artList,
  vsbTable,
  centreList,
  rightList,
}

class AnnouncementSource {
  const AnnouncementSource({
    required this.id,
    required this.name,
    required this.listUrl,
    required this.format,
    this.studentOnly = false,
  });

  final String id;
  final String name;
  final String listUrl;
  final AnnouncementListFormat format;

  /// A few mixed-purpose columns include notices addressed only to staff.
  final bool studentOnly;

  static const officialId = 'shu';

  static const official = AnnouncementSource(
    id: officialId,
    name: '上海大学官网',
    listUrl: 'https://www.shu.edu.cn/tzgg.htm',
    format: AnnouncementListFormat.shuHome,
  );

  static const all = <AnnouncementSource>[
    official,
    AnnouncementSource(
      id: 'bksy',
      name: '本科生院',
      listUrl: 'https://bksy.shu.edu.cn/index/tzgg.htm',
      format: AnnouncementListFormat.onlyList,
      studentOnly: true,
    ),
    AnnouncementSource(
      id: 'xgb',
      name: '本科生处',
      listUrl: 'https://xgb.shu.edu.cn/xgdt/tzgg.htm',
      format: AnnouncementListFormat.artList,
      studentOnly: true,
    ),
    AnnouncementSource(
      id: 'dwygb',
      name: '研究生工作部',
      listUrl: 'https://dwygb.shu.edu.cn/xwzx/tzgg.htm',
      format: AnnouncementListFormat.artList,
    ),
    AnnouncementSource(
      id: 'gs',
      name: '研究生院 · 培养管理',
      listUrl: 'https://gs.shu.edu.cn/xwlb/py.htm',
      format: AnnouncementListFormat.vsbTable,
    ),
    AnnouncementSource(
      id: 'cwc',
      name: '财务处',
      listUrl: 'https://cwc.shu.edu.cn/index/tzgg.htm',
      format: AnnouncementListFormat.centreList,
    ),
    AnnouncementSource(
      id: 'lib',
      name: '图书馆',
      listUrl: 'https://lib.shu.edu.cn/sho/ggxx.htm',
      format: AnnouncementListFormat.rightList,
    ),
  ];

  static AnnouncementSource byId(String? id) {
    for (final source in all) {
      if (source.id == id) return source;
    }
    return official;
  }
}
