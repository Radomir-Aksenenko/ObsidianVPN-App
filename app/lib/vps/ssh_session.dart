import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

/// Output of a remote command.
class CmdResult {
  const CmdResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final String stdout;
  final String stderr;
  final int exitCode;

  bool get ok => exitCode == 0;
}

/// Logger for transfer details. Must never receive secrets.
typedef SshLog = void Function(String line);

/// Thin wrapper over dartssh2 [SSHClient].
///
/// Host keys use trust on first use: when [VpsCredentials.hostKeyFingerprint] is
/// null the key is accepted and exposed as [hostKeyFingerprint] so the caller can
/// store it. When it is set and differs, [HostKeyChangedException] is thrown.
class SshSession {
  SshSession._(this._client, this.hostKeyFingerprint, this._log);

  final SSHClient _client;
  final SshLog? _log;

  /// OpenSSH-style SHA256 fingerprint of the server host key ("SHA256:...").
  final String hostKeyFingerprint;

  static const Duration connectTimeout = Duration(seconds: 12);
  static const Duration keepAliveInterval = Duration(seconds: 10);
  static const Duration authTimeout = Duration(seconds: 15);

  /// Opens the SSH connection and authenticates. Throws [VpsException] or
  /// [HostKeyChangedException].
  static Future<SshSession> connect(
    VpsCredentials creds, {
    SshLog? log,
  }) async {
    final host = creds.host.trim();
    if (host.isEmpty) {
      throw const VpsException('Укажите адрес сервера.');
    }
    if (creds.port <= 0 || creds.port > 65535) {
      throw const VpsException('Порт SSH должен быть от 1 до 65535.');
    }
    final user = creds.user.trim().isEmpty ? 'root' : creds.user.trim();
    final pinned = creds.hostKeyFingerprint;

    final identities = creds.usesKey ? _loadIdentities(creds) : null;

    SSHSocket socket;
    try {
      socket = await SSHSocket.connect(
        host,
        creds.port,
        timeout: connectTimeout,
      );
    } on TimeoutException {
      throw VpsException(
        'SSH не ответил за ${connectTimeout.inSeconds} с (${creds.port}). '
        'Порт закрыт или фильтруется.',
      );
    } catch (_) {
      throw VpsException('Не удалось подключиться к $host:${creds.port}.');
    }

    String? seen;
    String? mismatch;
    final client = SSHClient(
      socket,
      username: user,
      keepAliveInterval: keepAliveInterval,
      identities: identities,
      onPasswordRequest: creds.usesKey ? null : () => creds.password ?? '',
      onVerifyHostKey: (type, digest) {
        final fp = formatFingerprint(digest);
        seen = fp;
        if (pinned == null || pinned.isEmpty || fp == pinned) return true;
        mismatch = fp;
        return false;
      },
    );

    try {
      await client.authenticated.timeout(authTimeout);
    } on TimeoutException {
      client.close();
      throw const VpsException('Таймаут аутентификации по SSH (15 с).');
    } catch (e) {
      client.close();
      if (mismatch != null) {
        throw HostKeyChangedException(expected: pinned!, actual: mismatch!);
      }
      if (e is SSHAuthError) {
        throw VpsException(
          creds.usesKey
              ? 'Ошибка аутентификации по SSH-ключу.'
              : 'Ошибка аутентификации: проверьте логин и пароль.',
        );
      }
      throw const VpsException('Не удалось установить SSH-соединение.');
    }

    final fingerprint = seen ?? '';
    if (fingerprint.isEmpty) {
      client.close();
      throw const VpsException('Сервер не передал ключ хоста.');
    }
    return SshSession._(client, fingerprint, log);
  }

  /// SHA256 fingerprint in OpenSSH form: "SHA256:" + unpadded base64 of the digest.
  static String formatFingerprint(Uint8List digest) {
    return 'SHA256:${base64.encode(digest).replaceAll('=', '')}';
  }

  static List<SSHKeyPair> _loadIdentities(VpsCredentials creds) {
    final passphrase = creds.passphrase;
    try {
      return SSHKeyPair.fromPem(
        creds.privateKeyPem!.trim(),
        (passphrase == null || passphrase.isEmpty) ? null : passphrase,
      );
    } catch (_) {
      throw const VpsException(
        'Не удалось прочитать SSH-ключ. Нужен приватный ключ в формате PEM '
        '(не .pub), при необходимости укажите парольную фразу.',
      );
    }
  }

  /// Runs [cmd] on the server and collects stdout, stderr and the exit code.
  Future<CmdResult> run(
    String cmd, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final session = await _client.execute(cmd);
    final out = BytesBuilder(copy: false);
    final err = BytesBuilder(copy: false);
    try {
      await Future.wait<void>([
        session.stdout.forEach(out.add),
        session.stderr.forEach(err.add),
        session.done,
      ]).timeout(timeout);
    } on TimeoutException {
      session.close();
      throw VpsException(
        'Команда на сервере не завершилась за ${timeout.inSeconds} с.',
      );
    }
    return CmdResult(
      stdout: utf8.decode(out.takeBytes(), allowMalformed: true).trim(),
      stderr: utf8.decode(err.takeBytes(), allowMalformed: true).trim(),
      exitCode: session.exitCode ?? -1,
    );
  }

  /// Writes [data] to [remotePath] (creating parent directories) through SFTP.
  /// Falls back to `cat` over an exec channel when SFTP is unavailable, and checks
  /// the size of the remote file afterwards.
  /// When [mode] is set, the file permissions are changed to it (e.g. 0x1ed = 0755).
  Future<void> upload(Uint8List data, String remotePath, {int? mode}) async {
    final slash = remotePath.lastIndexOf('/');
    if (slash > 0) {
      final dir = remotePath.substring(0, slash);
      final made = await run('mkdir -p ${shellQuote(dir)}');
      if (!made.ok) {
        throw VpsException('Не удалось создать каталог $dir: ${made.stderr}');
      }
    }
    try {
      await _uploadSftp(data, remotePath);
    } catch (e) {
      _log?.call('SFTP недоступен, передача через exec: ${_short(e)}');
      try {
        await _uploadStream(data, remotePath);
      } on TimeoutException {
        throw VpsException('Передача $remotePath не завершилась за 5 минут.');
      }
    }
    final size = await run('wc -c < ${shellQuote(remotePath)}');
    if (!size.ok || int.tryParse(size.stdout.trim()) != data.length) {
      throw VpsException(
        'Файл $remotePath записан не полностью (${size.stdout.trim()} из ${data.length} байт).',
      );
    }
    if (mode != null) {
      final chmod = await run(
        'chmod ${mode.toRadixString(8)} ${shellQuote(remotePath)}',
      );
      if (!chmod.ok) {
        throw VpsException('Не удалось выставить права на $remotePath.');
      }
    }
  }

  Future<void> _uploadSftp(Uint8List data, String remotePath) async {
    final sftp = await _client.sftp();
    try {
      final file = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      try {
        await file.writeBytes(data);
      } finally {
        await file.close();
      }
    } finally {
      sftp.close();
    }
  }

  Future<void> _uploadStream(Uint8List data, String remotePath) async {
    final tmp = '/tmp/.obsidian-upload-${Random.secure().nextInt(1 << 31)}';
    final session = await _client.execute(streamUploadCommand(tmp, remotePath));
    session.stdin.add(data);
    await session.stdin.close();
    final err = BytesBuilder(copy: false);
    await Future.wait<void>([
      session.stderr.forEach(err.add),
      session.done,
    ]).timeout(const Duration(minutes: 5));
    if ((session.exitCode ?? -1) != 0) {
      final detail = utf8.decode(err.takeBytes(), allowMalformed: true).trim();
      throw VpsException(
        'Не удалось записать $remotePath на сервер${detail.isEmpty ? '' : ': $detail'}',
      );
    }
  }

  /// Closes the connection. Safe to call more than once.
  void close() => _client.close();

  static String _short(Object e) {
    final text = e.toString();
    return text.length > 160 ? text.substring(0, 160) : text;
  }
}

/// Single-quotes [value] for a POSIX shell. A quote inside is closed, escaped and
/// reopened.
String shellQuote(String value) {
  const closeEscapeReopen = r"'\''";
  return "'${value.replaceAll("'", closeEscapeReopen)}'";
}

/// Remote command of the exec upload fallback. `umask 077` keeps the temp file (it may
/// hold the server private key) unreadable for other users; a leftover temp file is
/// removed when the copy fails.
String streamUploadCommand(String tmp, String remotePath) =>
    'umask 077; cat > ${shellQuote(tmp)} && mv -f ${shellQuote(tmp)} ${shellQuote(remotePath)} '
    '|| { rm -f ${shellQuote(tmp)}; exit 1; }';
