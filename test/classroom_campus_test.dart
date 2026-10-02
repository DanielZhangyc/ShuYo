import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/classroom.dart';
import 'package:shuyo/data/services/classroom_api_client.dart';

void main() {
  test('groups B楼 with 宝山 despite the malformed source fullName', () {
    final options = ClassroomApiClient.parseSearchOptions(
      {
        'data': {
          'buildList': [
            {
              'id': 303,
              'name': 'A楼',
              'parentNodeId': 3,
              'fullName': '上海大学/宝山校区/A楼',
            },
            {
              'id': 122,
              'name': 'B楼',
              'parentNodeId': 3,
              'fullName': '上海大学/宝山校区B楼',
            },
          ],
        },
      },
      {
        'data': {'section': []},
      },
    );

    expect(options.campusNames, ['宝山']);
    expect(options.buildings.last.campusName, '宝山');
  });

  test('corrects the previously cached B楼 campus name', () {
    final options = ClassroomSearchOptions.fromJson({
      'buildings': [
        {
          'id': 122,
          'name': 'B楼',
          'campusId': 3,
          'campusName': '宝山B楼',
          'fullName': '上海大学/宝山校区B楼',
        },
      ],
      'sections': [],
    });

    expect(options.campusNames, ['宝山']);
  });
}
