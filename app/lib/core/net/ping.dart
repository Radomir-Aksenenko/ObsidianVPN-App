import 'dart:io';

/// Default connect timeout for [tcpPing].
const Duration kPingTimeout = Duration(milliseconds: 1500);

/// Measures the TCP connect time to [host]:[port] in milliseconds.
///
/// Returns null when the connection fails or does not complete within
/// [timeout]. Never throws.
Future<int?> tcpPing(
  String host,
  int port, {
  Duration timeout = kPingTimeout,
}) async {
  final watch = Stopwatch()..start();
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    watch.stop();
    socket.destroy();
    return watch.elapsedMilliseconds;
  } on Object {
    return null;
  }
}
