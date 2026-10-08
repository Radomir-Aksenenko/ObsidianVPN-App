// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Obsidian';

  @override
  String get navHome => 'Home';

  @override
  String get navServers => 'Servers';

  @override
  String get navAccess => 'Access';

  @override
  String get navSettings => 'Settings';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowClose => 'Close';

  @override
  String get homeWordmark => 'obsidian';

  @override
  String get homeStatusDisconnected => 'DISCONNECTED';

  @override
  String homeStatusConnecting(int stage) {
    return 'CONNECTING $stage/4';
  }

  @override
  String get homeStatusConnected => 'PROTECTED';

  @override
  String get homeStatusReconnecting => 'RECONNECTING';

  @override
  String get homeStatusDisconnecting => 'DISCONNECTING';

  @override
  String get homeStatusError => 'ERROR';

  @override
  String get homeActionConnect => 'Connect';

  @override
  String get homeActionCancel => 'Cancel';

  @override
  String get homeActionDisconnect => 'Disconnect';

  @override
  String get homeActionRetry => 'Retry';

  @override
  String get homeActionDisconnecting => 'Disconnecting';

  @override
  String get homeLogs => 'Log';

  @override
  String get logsTitle => 'Log';

  @override
  String get logsCopyAll => 'Copy all';

  @override
  String get logsCopied => 'Log copied';

  @override
  String get logsEmpty => 'No entries yet';

  @override
  String get homeServerPickerTitle => 'Server';

  @override
  String get homeNoServers => 'Add your first server: paste an access key.';

  @override
  String get homeAddServer => 'Add server';

  @override
  String get homeSplitTitle => 'Split tunnel';

  @override
  String get trafficDownload => 'Download';

  @override
  String get trafficUpload => 'Upload';

  @override
  String trafficTotal(String value) {
    return 'Total $value';
  }

  @override
  String get unitKbps => 'kbit/s';

  @override
  String get unitMbps => 'Mbit/s';

  @override
  String get unitGbps => 'Gbit/s';

  @override
  String get unitByte => 'B';

  @override
  String get unitKilobyte => 'KB';

  @override
  String get unitMegabyte => 'MB';

  @override
  String get unitGigabyte => 'GB';

  @override
  String pingMs(int ms) {
    return '$ms ms';
  }

  @override
  String get pingNoReply => 'no reply';

  @override
  String get sheetClose => 'Close';
}
