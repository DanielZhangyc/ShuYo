import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/models/post.dart';
import 'package:shuyo/data/models/topic.dart';
import 'package:shuyo/data/models/topic_detail.dart';
import 'package:shuyo/data/services/forum_read_position_store.dart';
import 'package:shuyo/features/topic/topic_page.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('toggles between threaded and independent reverse order',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final posts = [
      _post(1, 'floor one'),
      _post(2, 'floor two'),
      _post(3, 'floor three', replyTo: 2),
      _post(4, 'floor four', replyTo: 3),
    ];
    final detail = TopicDetail(
      id: 10,
      title: '排序测试',
      categoryId: 1,
      postsCount: posts.length,
      highestPostNumber: 4,
      canCreatePost: false,
      canDelete: false,
      posts: posts,
    );

    await tester.pumpWidget(_app(detail));
    await tester.pump();

    expect(find.byTooltip('按最新楼层倒序'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('topic-order-toggle')));
    await tester.pump();

    expect(find.byTooltip('恢复楼中楼排序'), findsOneWidget);
    expect(find.text('#4'), findsOneWidget);
    expect(find.text('回复 #3'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('floor four', findRichText: true)).dy,
      lessThan(
        tester.getTopLeft(find.text('floor three', findRichText: true)).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.text('floor three', findRichText: true)).dy,
      lessThan(
        tester.getTopLeft(find.text('floor two', findRichText: true)).dy,
      ),
    );
  });

  testWidgets('restoring a hidden reply expands its thread', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final posts = [
      for (var number = 1; number <= 22; number++)
        _post(number, 'floor $number', topicId: 11),
      _post(23, 'floor 23', replyTo: 22, topicId: 11),
      _post(24, 'floor 24', replyTo: 22, topicId: 11),
      _post(25, 'floor 25', replyTo: 22, topicId: 11),
    ];
    final detail = TopicDetail(
      id: 11,
      title: '位置恢复测试',
      categoryId: 1,
      postsCount: posts.length,
      highestPostNumber: 25,
      canCreatePost: false,
      canDelete: false,
      posts: posts,
    );
    final key = ForumReadPositionStore.topicKey(
      username: 'tester',
      topicId: 11,
    );
    await ForumReadPositionStore.save(
      key,
      120,
      anchorPostNumber: 25,
    );

    await tester.pumpWidget(_app(detail));
    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('收起回复'), findsOneWidget);
    final target = find.text('#25');
    expect(target, findsOneWidget);
    expect(
      tester.getRect(target).overlaps(
            tester.getRect(find.byType(ListView).first),
          ),
      isTrue,
    );
  });

  testWidgets('notification target still locates a distant hidden reply',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final posts = [
      for (var number = 1; number <= 22; number++)
        _post(number, 'floor $number', topicId: 12),
      _post(23, 'floor 23', replyTo: 22, topicId: 12),
      _post(24, 'floor 24', replyTo: 22, topicId: 12),
      _post(25, 'floor 25', replyTo: 22, topicId: 12),
    ];
    final detail = TopicDetail(
      id: 12,
      title: '通知定位测试',
      categoryId: 1,
      postsCount: posts.length,
      highestPostNumber: 25,
      canCreatePost: false,
      canDelete: false,
      posts: posts,
    );

    await tester.pumpWidget(_app(detail, targetPostNumber: 25));
    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final target = find.text('#25');
    expect(target, findsOneWidget);
    expect(
      tester.getRect(target).overlaps(
            tester.getRect(find.byType(ListView).first),
          ),
      isTrue,
    );
  });
}

Widget _app(TopicDetail detail, {int? targetPostNumber}) {
  return MaterialApp(
    theme: ShuYoThemes.byId(ShuYoThemes.defaultId).themeData(),
    home: Scaffold(
      body: TopicPage(
        item: TopicListItem(
          id: detail.id,
          title: detail.title,
          postsCount: detail.postsCount,
          replyCount: detail.postsCount - 1,
          highestPostNumber: detail.highestPostNumber,
          views: 0,
          likeCount: 0,
          categoryId: detail.categoryId,
          posters: const [],
        ),
        detail: detail,
        targetPostNumber: targetPostNumber,
        category: null,
        currentUsername: 'tester',
        isOnline: true,
        isSubmittingReply: false,
        busyLikePostIds: const {},
        busyPollKeys: const {},
        busyDeletePostIds: const {},
        busyReportPostIds: const {},
        reportedPostIds: const {},
        onCreateReply: (_) async => true,
        onUploadImage: (_) => throw UnimplementedError(),
        onLikePost: (_) {},
        onVotePoll: (_, __, ___) async {},
        onTogglePollStatus: (_, __, ___) async {},
        onDeletePost: (_) {},
        onReportPost: (_) {},
        onOpenUser: (_) {},
        onOpenInternalTopic: (_) {},
        onSearchUsers: (_) async => const [],
        onLoginRequired: () {},
      ),
    ),
  );
}

Post _post(
  int postNumber,
  String text, {
  int? replyTo,
  int topicId = 10,
}) {
  return Post(
    id: postNumber,
    topicId: topicId,
    username: 'user$postNumber',
    avatarTemplate: '',
    cooked: '<p>$text</p>',
    postNumber: postNumber,
    postUrl: '/t/topic/$topicId/$postNumber',
    replyToPostNumber: replyTo,
    actions: const [],
  );
}
