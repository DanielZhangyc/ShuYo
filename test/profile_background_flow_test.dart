import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/composer.dart';
import 'package:shuyo/data/models/discourse_user.dart';
import 'package:shuyo/data/models/user_profile.dart';
import 'package:shuyo/data/repositories/forum_repository.dart';
import 'package:shuyo/features/profile/background_crop_page.dart';
import 'package:shuyo/features/profile/profile_header.dart';
import 'package:shuyo/features/profile/profile_settings_page.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';

final _source = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAwAAAAICAIAAABChommAAAAEUlEQVR4nGP4z8BAEDGMKgIArIFfoRxYlTsAAAAASUVORK5CYII=',
);
final _cropped = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAYAAAACCAIAAAD0PzoJAAAAD0lEQVR4nGNgYPiPgTCEANdOC/UUsKYZAAAAAElFTkSuQmCC',
);
const _pickerChannel = MethodChannel('work.shuyo.app/image_picker');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Object? pickerResult;

  setUp(() {
    pickerResult = <String, Object?>{
      'bytes': _source,
      // The original metadata must not leak into the encoded crop upload.
      'filename': 'camera.heic',
      'mimeType': 'image/heic',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, (call) async {
      expect(call.method, 'pickImage');
      return pickerResult;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, null);
  });

  for (final width in [360.0, 430.0, 840.0]) {
    testWidgets('crop matches the actual header at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpPage(tester, _BackgroundRepository());
      final headerWidth = tester.getSize(find.byType(ProfileHeader)).width;

      await _openCrop(tester);
      final crop = tester.widget<BackgroundCropPage>(
        find.byType(BackgroundCropPage),
      );
      expect(crop.aspectRatio, closeTo(headerWidth / 122, 0.000001));
      await _returnFromCrop(tester, null);
    });
  }

  testWidgets('rotation during picking and cropping uses the current width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pendingPick = Completer<Object?>();
    pickerResult = pendingPick.future;
    await _pumpPage(tester, _BackgroundRepository());
    await _tapPick(tester);
    await tester.pump();
    tester.view.physicalSize = const Size(840, 900);
    await tester.pump();
    pendingPick.complete({'bytes': _source});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    BackgroundCropPage cropPage() =>
        tester.widget<BackgroundCropPage>(find.byType(BackgroundCropPage));
    expect(cropPage().aspectRatio, closeTo((840 - 32) / 122, 0.000001));

    tester.view.physicalSize = const Size(430, 900);
    await tester.pump();
    expect(cropPage().aspectRatio, closeTo((430 - 32) / 122, 0.000001));
    await _returnFromCrop(tester, _cropped);
    expect(tester.getSize(find.byType(ProfileHeader)).width, 398);
  });
  testWidgets('confirming on a short screen scrolls the preview into view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpPage(tester, _BackgroundRepository());
    await _openCrop(tester);
    await _returnFromCrop(tester, _cropped);
    expect(_header(tester).backgroundBytes, orderedEquals(_cropped));
    final headerRect = tester.getRect(find.byType(ProfileHeader));
    expect(headerRect.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(headerRect.bottom, lessThanOrEqualTo(400));
  });
  testWidgets('picker and crop cancellation preserve the saved background', (
    tester,
  ) async {
    final repository = _BackgroundRepository(backgroundUrl: '/old.png');
    await _pumpPage(tester, repository);
    pickerResult = null;
    await _tapPick(tester);
    await tester.pumpAndSettle();
    expect(find.byType(BackgroundCropPage), findsNothing);
    expect(_header(tester).backgroundBytes, isNull);
    expect(_header(tester).backgroundUrl, endsWith('/old.png'));
    expect(_save(tester).onPressed, isNull);

    pickerResult = {'bytes': _source};
    await _openCrop(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_header(tester).backgroundBytes, isNull);
    expect(_header(tester).backgroundUrl, endsWith('/old.png'));
    expect(_save(tester).onPressed, isNull);
    expect(repository.uploads, isEmpty);
  });

  testWidgets('confirmed crop previews locally and save uploads cropped bytes',
      (
    tester,
  ) async {
    final repository = _BackgroundRepository();
    await _pumpPage(tester, repository);
    await _openCrop(tester);
    expect(repository.uploads, isEmpty);
    await _returnFromCrop(tester, _cropped);

    expect(_header(tester).backgroundBytes, orderedEquals(_cropped));
    expect(repository.uploads, isEmpty);
    expect(repository.savedDraft, isNull);
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(repository.uploads, hasLength(1));
    final uploaded = repository.uploads.single;
    expect(uploaded.bytes, orderedEquals(_cropped));
    expect(uploaded.bytes, isNot(orderedEquals(_source)));
    expect(uploaded.filename, 'profile-background.png');
    expect(uploaded.mimeType, 'image/png');
    expect(
      repository.savedDraft?.profileBackgroundUploadUrl,
      '/uploaded-1.png',
    );
    expect(_header(tester).backgroundBytes, isNull);
    expect(_save(tester).onPressed, isNull);

    // Reopening reads the uploaded URL from the repository, not a local offset.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpPage(tester, repository);
    expect(_header(tester).backgroundUrl, endsWith('/uploaded-1.png'));
  });

  testWidgets('cancelling a replacement preserves a confirmed unsaved crop', (
    tester,
  ) async {
    final repository = _BackgroundRepository();
    await _pumpPage(tester, repository);
    await _openCrop(tester);
    await _returnFromCrop(tester, _cropped);
    await _openCrop(tester);
    await _returnFromCrop(tester, null);
    expect(_header(tester).backgroundBytes, orderedEquals(_cropped));
    expect(repository.uploads, isEmpty);
    expect(_save(tester).onPressed, isNotNull);
  });

  testWidgets('cancelling after clear keeps the staged clear operation', (
    tester,
  ) async {
    final repository = _BackgroundRepository(backgroundUrl: '/old.png');
    await _pumpPage(tester, repository);
    final clear = find.widgetWithText(OutlinedButton, '清除背景');
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pump();
    await _openCrop(tester);
    await _returnFromCrop(tester, null);
    expect(_header(tester).backgroundUrl, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.savedDraft?.profileBackgroundUploadUrl, isEmpty);
    expect(repository.uploads, isEmpty);
  });

  testWidgets('upload failure keeps the crop and retries on save', (
    tester,
  ) async {
    final repository = _BackgroundRepository()..failUpload = true;
    await _pumpPage(tester, repository);
    await _openCrop(tester);
    await _returnFromCrop(tester, _cropped);
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.savedDraft, isNull);
    expect(_header(tester).backgroundBytes, orderedEquals(_cropped));
    expect(find.textContaining('保存未完成'), findsOneWidget);
    expect(_save(tester).onPressed, isNotNull);

    repository.failUpload = false;
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.uploads, hasLength(2));
    expect(repository.uploads.last.bytes, orderedEquals(_cropped));
    expect(
      repository.savedDraft?.profileBackgroundUploadUrl,
      '/uploaded-2.png',
    );
  });

  testWidgets('settings retry reuses upload unless another crop is confirmed', (
    tester,
  ) async {
    final repository = _BackgroundRepository()..failSettings = true;
    await _pumpPage(tester, repository);
    await _openCrop(tester);
    await _returnFromCrop(tester, _cropped);
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.uploads, hasLength(1));

    await _openCrop(tester);
    await _returnFromCrop(tester, null);
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.uploads, hasLength(1));

    await _openCrop(tester);
    await _returnFromCrop(tester, _source);
    repository.failSettings = false;
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.uploads, hasLength(2));
    expect(repository.uploads.last.bytes, orderedEquals(_source));
    expect(
      repository.savedDraft?.profileBackgroundUploadUrl,
      '/uploaded-2.png',
    );
  });
}

Future<void> _pumpPage(WidgetTester tester, ForumRepository repository) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ShuYoThemes.byId(ShuYoThemes.defaultId).themeData(),
      home: ProfileSettingsPage(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapPick(WidgetTester tester) async {
  final pick = find.widgetWithText(
    OutlinedButton,
    _header(tester).backgroundBytes != null ||
            (_header(tester).backgroundUrl?.isNotEmpty ?? false)
        ? '更换背景图片'
        : '选择背景图片',
  );
  await tester.scrollUntilVisible(
    pick,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(pick);
}

Future<void> _openCrop(WidgetTester tester) async {
  await _tapPick(tester);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(BackgroundCropPage), findsOneWidget);
}

Future<void> _returnFromCrop(WidgetTester tester, Uint8List? result) async {
  Navigator.of(tester.element(find.byType(BackgroundCropPage))).pop(result);
  await tester.pumpAndSettle();
}

ProfileHeader _header(WidgetTester tester) =>
    tester.widget<ProfileHeader>(find.byType(ProfileHeader));
TextButton _save(WidgetTester tester) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, '保存'));

class _BackgroundRepository implements ForumRepository {
  _BackgroundRepository({String backgroundUrl = ''})
      : current = UserProfile(
          user: const DiscourseUser(
              id: 1, username: 'tester', avatarTemplate: ''),
          profileBackgroundUploadUrl: backgroundUrl,
          canEdit: true,
          canUploadProfileHeader: true,
        );

  UserProfile current;
  final uploads = <PickedImage>[];
  ProfileSettingsDraft? savedDraft;
  bool failUpload = false;
  bool failSettings = false;

  @override
  Future<UserProfile> fetchCurrentUserProfile({
    bool forceRefresh = false,
  }) async =>
      current;

  @override
  Future<ProfileImageUpload> uploadProfileImage(
    PickedImage image,
    ProfileImageUploadType type,
  ) async {
    expect(type, ProfileImageUploadType.profileBackground);
    uploads.add(image);
    if (failUpload) throw StateError('upload unavailable');
    return ProfileImageUpload(
      id: uploads.length,
      url: '/uploaded-${uploads.length}.png',
      filename: image.filename,
      width: 6,
      height: 2,
    );
  }

  @override
  Future<UserProfile> updateProfileSettings(ProfileSettingsDraft draft) async {
    if (failSettings) throw StateError('settings unavailable');
    savedDraft = draft;
    return current = UserProfile(
      user: current.user,
      bioRaw: draft.bioRaw,
      profileBackgroundUploadUrl: draft.profileBackgroundUploadUrl,
      hideProfile: draft.hideProfile,
      canEdit: true,
      canUploadProfileHeader: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
