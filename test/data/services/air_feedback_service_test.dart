import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/services/air_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.work.shuyo.app/feedback');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('iOS sends the title and content as one message', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });

    const bridge = NativeAirFeedbackBridge(
      channel: channel,
      platform: TargetPlatform.iOS,
    );
    await bridge.send(title: 'Title', content: 'Body');

    expect(received?.method, 'send');
    expect(received?.arguments, {'message': 'Title\n\nBody'});
  });

  test('Android does not invoke the AirFeedback channel', () async {
    var invoked = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      invoked = true;
      throw StateError('must not be called on Android');
    });

    const bridge = NativeAirFeedbackBridge(
      channel: channel,
      platform: TargetPlatform.android,
    );
    await bridge.send(title: 'Title', content: 'Body');

    expect(invoked, isFalse);
  });

  test('AirFeedback failure does not block legacy success', () async {
    var airStarted = false;
    var legacyCompleted = false;
    final service = ClientFeedbackSubmissionService(
      bridge: _FailingBridge(() => airStarted = true),
    );

    await service.submit(
      title: 'Title',
      content: 'Body',
      submitLegacy: () async {
        expect(airStarted, isTrue);
        legacyCompleted = true;
      },
    );

    expect(legacyCompleted, isTrue);
  });

  test('a pending AirFeedback request does not block legacy success', () async {
    var legacyCompleted = false;
    final service = ClientFeedbackSubmissionService(
      bridge: _PendingBridge(),
    );

    await service.submit(
      title: 'Title',
      content: 'Body',
      submitLegacy: () async {
        legacyCompleted = true;
      },
    );

    expect(legacyCompleted, isTrue);
  });
}

class _PendingBridge implements AirFeedbackBridge {
  @override
  Future<void> send({required String title, required String content}) {
    return Completer<void>().future;
  }
}

class _FailingBridge implements AirFeedbackBridge {
  _FailingBridge(this.onSend);

  final VoidCallback onSend;

  @override
  Future<void> send({required String title, required String content}) {
    onSend();
    return Future<void>.error(StateError('AirFeedback failed'));
  }
}
