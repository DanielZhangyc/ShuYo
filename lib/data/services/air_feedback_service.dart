import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The optional native destination for feedback submitted from the client page.
abstract interface class AirFeedbackBridge {
  Future<void> send({required String title, required String content});
}

/// Sends feedback to the iOS AirFeedback endpoint when that bridge exists.
///
/// Android and other platforms deliberately do nothing; the legacy feedback
/// API remains the source of truth for every platform.
class NativeAirFeedbackBridge implements AirFeedbackBridge {
  const NativeAirFeedbackBridge({
    MethodChannel channel = const MethodChannel('work.shuyo.app/feedback'),
    TargetPlatform? platform,
  })  : _channel = channel,
        _platform = platform;

  final MethodChannel _channel;
  final TargetPlatform? _platform;

  @override
  Future<void> send({required String title, required String content}) async {
    if ((_platform ?? defaultTargetPlatform) != TargetPlatform.iOS) {
      return;
    }
    await _channel.invokeMethod<void>('send', <String, String>{
      'message': '$title\n\n$content',
    });
  }
}

/// Runs the legacy submission while starting the optional iOS submission.
///
/// The native submission is intentionally best effort: its result is never
/// allowed to alter the result of the legacy API or its user-facing message.
class ClientFeedbackSubmissionService {
  const ClientFeedbackSubmissionService({required AirFeedbackBridge bridge})
      : _bridge = bridge;

  final AirFeedbackBridge _bridge;

  Future<void> submit({
    required Future<void> Function() submitLegacy,
    required String title,
    required String content,
  }) async {
    unawaited(_sendAirFeedback(title: title, content: content));
    await submitLegacy();
  }

  Future<void> _sendAirFeedback({
    required String title,
    required String content,
  }) async {
    try {
      await _bridge.send(title: title, content: content);
    } on Object {
      // AirFeedback is an optional mirror and must never affect legacy
      // feedback submission or its success state.
    }
  }
}

const defaultAirFeedbackBridge = NativeAirFeedbackBridge();
