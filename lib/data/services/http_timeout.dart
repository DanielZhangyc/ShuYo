import 'dart:async';

class HttpTimeout {
  const HttpTimeout._();

  /// Fast availability checks that must not block the main user flow.
  static const probe = Duration(seconds: 3);

  /// DNS, TCP, and TLS connection establishment.
  static const connect = Duration(seconds: 5);

  /// A complete ordinary API request, including its response body.
  static const normal = Duration(seconds: 10);

  /// A single WeCom scan long-poll request, which the server keeps open
  /// (about 40s) until a scan event arrives or it times out.
  static const longPoll = Duration(seconds: 45);

  /// A user-visible operation composed of multiple ordinary requests.
  static const composed = Duration(seconds: 20);

  /// Discovery of the redirect-based native campus authentication entry.
  static const authentication = Duration(seconds: 30);

  /// OAuth callback, cookie exchange, and service ticket establishment.
  static const oauthCompletion = Duration(seconds: 45);

  /// A complete upload or download operation.
  static const transfer = Duration(seconds: 30);

  /// Maximum time a response stream may make no progress.
  static const streamIdle = Duration(seconds: 10);

  static Future<T> request<T>(
    Future<T> future, {
    Duration timeout = normal,
    String message = '网络请求超时，请稍后再试',
  }) {
    return future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(message, timeout),
    );
  }
}
