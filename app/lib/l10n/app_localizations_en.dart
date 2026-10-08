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

  @override
  String get accessServers => 'My servers';

  @override
  String get accessKeys => 'Issued keys';

  @override
  String get accessDeploy => 'Deploy server';

  @override
  String get accessIssue => 'Issue key';

  @override
  String get accessIssueNeedsServer =>
      'Deploy your own server first. Keys are issued from it.';

  @override
  String get accessEmpty =>
      'Obsidian installs on a clean Ubuntu 22.04/24.04 or Debian 12 VPS, and you issue keys from it afterwards.';

  @override
  String get accessKeysEmpty =>
      'No keys yet. Issue one and it will appear here.';

  @override
  String get accessForever => 'Forever';

  @override
  String accessDaysLeft(int days) {
    return '$days days left';
  }

  @override
  String get accessExpired => 'Expired';

  @override
  String accessDevices(int count) {
    return 'Devices: $count';
  }

  @override
  String get accessNeedsUpdate => 'Update needed';

  @override
  String get accessKeyMore => 'Key actions';

  @override
  String get accessKeyDelete => 'Delete key';

  @override
  String get accessKeyDeleteTitle => 'Delete key?';

  @override
  String accessKeyDeleteText(String name) {
    return 'Key \"$name\" will be removed from the list. Revoking keys on the server is not supported yet, so it may keep working until the server is reset.';
  }

  @override
  String get accessKeyDeleted => 'Key deleted';

  @override
  String get accessIssueTitle => 'New key';

  @override
  String get accessIssueName => 'Name';

  @override
  String get accessIssueNameHint => 'Guest';

  @override
  String get accessIssueValidity => 'Validity';

  @override
  String get accessValidity7 => '7 days';

  @override
  String get accessValidity30 => '30 days';

  @override
  String get accessValidity90 => '90 days';

  @override
  String get accessIssueDevices => 'Devices';

  @override
  String get accessFewer => 'Fewer';

  @override
  String get accessMore => 'More';

  @override
  String get accessIssueServer => 'Server';

  @override
  String get accessIssueSubmit => 'Issue';

  @override
  String get accessKeyTitle => 'Key';

  @override
  String get accessKeyServer => 'Server';

  @override
  String get accessKeyExpiry => 'Validity';

  @override
  String get accessKeyDevicesLabel => 'Devices';

  @override
  String get accessKeyCopyLink => 'Copy link';

  @override
  String get accessKeyCopyKey => 'Copy key';

  @override
  String get accessKeyShowKey => 'Show key as text';

  @override
  String get accessKeyQrHint =>
      'Scan the QR code in Obsidian on another device.';

  @override
  String accessKeyExpiresOn(String date) {
    return 'Until $date';
  }

  @override
  String get accessCopied => 'Copied';

  @override
  String get vpsDeployTitle => 'Deploy server';

  @override
  String get vpsDeployHint =>
      'A clean Ubuntu 22.04/24.04 or Debian 12 works. The password or key stays only on this device.';

  @override
  String get vpsHostLabel => 'IP or domain';

  @override
  String get vpsHostRequired => 'Enter an IP or domain.';

  @override
  String get vpsHostInvalid =>
      'The address looks wrong. Example: 203.0.113.10 or vps.example.net';

  @override
  String get vpsPortLabel => 'SSH port';

  @override
  String get vpsPortInvalid => 'Port must be from 1 to 65535.';

  @override
  String get vpsUserLabel => 'User';

  @override
  String get vpsUserRequired => 'Enter a user.';

  @override
  String get vpsAuthLabel => 'Sign in';

  @override
  String get vpsAuthPassword => 'Password';

  @override
  String get vpsAuthKey => 'SSH key';

  @override
  String get vpsPasswordLabel => 'Password';

  @override
  String get vpsPasswordRequired => 'Enter the password.';

  @override
  String get vpsPasswordShow => 'Show password';

  @override
  String get vpsPasswordHide => 'Hide password';

  @override
  String get vpsKeyFile => 'Choose key file';

  @override
  String vpsKeyFilePicked(String name) {
    return 'File: $name';
  }

  @override
  String get vpsKeyPasteLabel => 'Or paste the private key';

  @override
  String get vpsKeyRequired => 'Choose a file or paste the private key.';

  @override
  String get vpsKeyInvalid =>
      'This does not look like a private key. Expected a BEGIN ... PRIVATE KEY block.';

  @override
  String get vpsPassphraseLabel => 'Key passphrase, if any';

  @override
  String get vpsSniLabel => 'Masking site (SNI)';

  @override
  String get vpsSniCaption =>
      'The site the traffic is disguised as. Clients use the same address.';

  @override
  String get vpsSniHint => 'Domain, for example example.org';

  @override
  String get vpsSniInvalid => 'Enter a domain without https:// or a path.';

  @override
  String get vpsDeployStart => 'Deploy';

  @override
  String get vpsCancel => 'Cancel';

  @override
  String get vpsCancelDeployTitle => 'Stop installation?';

  @override
  String get vpsCancelDeployText =>
      'The server will be left half-installed. To finish, reinstall it on a clean VPS.';

  @override
  String get vpsCancelDeployAction => 'Stop';

  @override
  String get vpsStay => 'Keep going';

  @override
  String get vpsProgressTitle => 'Installing';

  @override
  String get vpsSheetRunning =>
      'Keep the app open until the operation finishes.';

  @override
  String get vpsConsole => 'Log';

  @override
  String get vpsCopyLog => 'Copy log';

  @override
  String get vpsLogCopied => 'Log copied';

  @override
  String get vpsRetry => 'Retry';

  @override
  String get vpsFailed => 'Operation failed';

  @override
  String get vpsSuccessTitle => 'Server is ready';

  @override
  String get vpsSuccessText =>
      'The owner key was added to Servers and selected. It is your own connection.';

  @override
  String get vpsAdminToken => 'Admin token';

  @override
  String get vpsAdminTokenWarning =>
      'Save it now, it will not be shown again. It is needed to manage keys on the server.';

  @override
  String get vpsCopy => 'Copy';

  @override
  String get vpsCopied => 'Copied';

  @override
  String get vpsDone => 'Done';

  @override
  String get vpsHostKeyTitle => 'Server key changed';

  @override
  String get vpsHostKeyText =>
      'The server\'s SSH fingerprint does not match the saved one. This happens after a VPS reinstall, but it can also mean the server was replaced. Trust the new key only if you reinstalled the server yourself.';

  @override
  String get vpsHostKeyExpected => 'Expected';

  @override
  String get vpsHostKeyActual => 'Received';

  @override
  String get vpsHostKeyTrust => 'Trust new key';

  @override
  String get vpsManageTitle => 'Server';

  @override
  String vpsBadgeReality(int port) {
    return 'REALITY :$port';
  }

  @override
  String get vpsBadgeIpv4 => 'IPv4';

  @override
  String get vpsBadgeDualStack => 'Dual-Stack';

  @override
  String get vpsBadgeCreds => 'SSH saved';

  @override
  String get vpsNoCreds =>
      'SSH access is not saved. Without it you cannot update the core or change settings.';

  @override
  String get vpsAddCreds => 'Add access';

  @override
  String get vpsSniSection => 'Masking (SNI)';

  @override
  String get vpsSniApply => 'Apply new SNI';

  @override
  String get vpsReissueNote =>
      'The owner key is rebuilt. Keys issued before must be issued again, because they carry the old settings.';

  @override
  String get vpsSniDone => 'SNI applied';

  @override
  String get vpsIpv6Section => 'IPv6';

  @override
  String get vpsIpv6Done => 'IPv6 setting saved';

  @override
  String get vpsCoreSection => 'Core';

  @override
  String vpsCoreVersion(String version) {
    return 'Version $version';
  }

  @override
  String get vpsUpdateNeeded => 'Update required';

  @override
  String get vpsUpToDate => 'Up to date';

  @override
  String get vpsCheckUpdates => 'Check for updates';

  @override
  String get vpsUpdate => 'Update';

  @override
  String get vpsUpdateDone => 'Core updated';

  @override
  String get vpsCheckLatest => 'The core is up to date.';

  @override
  String get vpsCheckOutdated => 'A newer core is available.';

  @override
  String get vpsSshSection => 'SSH access';

  @override
  String get vpsEditSsh => 'Edit access';

  @override
  String get vpsSaveSsh => 'Save';

  @override
  String get vpsSshSaved => 'Access saved';

  @override
  String get vpsResetAction => 'Reset server';

  @override
  String get vpsResetTitle => 'Reset server?';

  @override
  String get vpsResetText =>
      'All keys issued from this server will stop working. The server gets new keys and the owner key is rebuilt.';

  @override
  String get vpsResetConfirm => 'Reset';

  @override
  String get vpsResetDone => 'Server reset, owner key updated';

  @override
  String get vpsSheetCheck => 'Checking version';

  @override
  String get vpsSheetSni => 'Changing SNI';

  @override
  String get vpsSheetUpdate => 'Updating core';

  @override
  String get vpsSheetIpv6 => 'Setting IPv6';

  @override
  String get vpsSheetReset => 'Resetting server';

  @override
  String get vpsErrorGeneric => 'Something went wrong. Try again.';

  @override
  String get vpsOwnerKeyMissing =>
      'The owner key is not stored on this device. Reinstall the server to create it again.';

  @override
  String get serversTitle => 'Servers';

  @override
  String get serversSectionFavorites => 'Favorites';

  @override
  String get serversSectionAll => 'All servers';

  @override
  String get serversAddKey => 'Add key';

  @override
  String get serversScanQr => 'Scan QR';

  @override
  String get serversEmpty => 'Add your first server: paste an access key.';

  @override
  String get serversMore => 'Actions';

  @override
  String get serversActionRename => 'Rename';

  @override
  String get serversActionFavoriteAdd => 'Add to favorites';

  @override
  String get serversActionFavoriteRemove => 'Remove from favorites';

  @override
  String get serversActionSplit => 'Split tunnel';

  @override
  String get serversActionDelete => 'Delete';

  @override
  String get serversRenameTitle => 'New name';

  @override
  String get serversNameLabel => 'Name';

  @override
  String get serversNameHint => 'For example, Frankfurt';

  @override
  String get serversSave => 'Save';

  @override
  String get serversRenamed => 'Name saved';

  @override
  String get serversFavoriteAdded => 'Added to favorites';

  @override
  String get serversFavoriteRemoved => 'Removed from favorites';

  @override
  String get serversDeleteTitle => 'Delete server?';

  @override
  String get serversDeleteBody =>
      'The key for this server will be removed from this device. You can add the server back only by pasting its key again.';

  @override
  String get serversDeleteConfirm => 'Delete';

  @override
  String get serversCancel => 'Cancel';

  @override
  String get serversDeleted => 'Server deleted';

  @override
  String get serversDeleteBlocked => 'Disconnect from this server first.';

  @override
  String get serversAdded => 'Server added';

  @override
  String get serversAddFailed => 'Could not save the server. Try again.';

  @override
  String get serversClipboardEmpty => 'The clipboard has no text.';

  @override
  String get addKeyTitle => 'Add key';

  @override
  String get addKeyField => 'Access key';

  @override
  String get addKeyFieldHint => 'Paste a key or an obsidian:// link';

  @override
  String get addKeyPaste => 'Paste';

  @override
  String get addKeyNameField => 'Name, optional';

  @override
  String get addKeyNameHint => 'For example, Frankfurt';

  @override
  String addKeyRecognized(String hostPort) {
    return 'Recognized: $hostPort';
  }

  @override
  String get addKeySubmit => 'Add';

  @override
  String get qrTitle => 'Scan QR';

  @override
  String get qrHint => 'Point the camera at the key QR code';

  @override
  String get qrTorch => 'Torch';

  @override
  String get qrDeniedTitle => 'No camera access';

  @override
  String get qrDeniedBody =>
      'Allow camera access in system settings to scan a key. Or paste the key by hand.';

  @override
  String get qrError => 'The camera is unavailable. Paste the key by hand.';

  @override
  String get splitTitle => 'Split tunnel';

  @override
  String get splitModeOff => 'Off';

  @override
  String get splitModeInclude => 'Only listed';

  @override
  String get splitModeExclude => 'All except listed';

  @override
  String get splitOffNote =>
      'All traffic goes through the VPN. The list below is kept.';

  @override
  String get splitPresets => 'Presets';

  @override
  String splitPresetCount(int count) {
    return 'Addresses in the set: $count';
  }

  @override
  String get splitEntries => 'Custom rules';

  @override
  String get splitEntriesHint => 'A domain, IP or subnet on each line';

  @override
  String splitAccepted(int count) {
    return 'Accepted rules: $count';
  }

  @override
  String get splitIssues => 'Not recognized';

  @override
  String get splitEmptyWarning =>
      'The list is empty: nothing goes through the VPN right now.';

  @override
  String get splitNoteDomains => 'Domains are re-resolved every 10 minutes.';

  @override
  String get splitNoteWildcards =>
      'Wildcards like *.ru are not supported: list specific domains.';

  @override
  String get splitNoteIdn =>
      'Write Cyrillic domains in punycode, with the xn-- prefix.';

  @override
  String get splitSave => 'Save';

  @override
  String get splitSaved => 'Rules saved';

  @override
  String splitSavedSkipped(int count) {
    return 'Rules saved. Lines skipped: $count';
  }

  @override
  String get splitLiveNote =>
      'Changes apply to the current connection right away.';

  @override
  String get splitUnsavedTitle => 'Save changes?';

  @override
  String get splitUnsavedBody => 'The split tunnel was changed but not saved.';

  @override
  String get splitDiscard => 'Discard';

  @override
  String get splitKeepEditing => 'Keep editing';

  @override
  String get splitMissing => 'Server not found.';

  @override
  String get settingsSectionConnection => 'Connection';

  @override
  String get settingsAutoConnect => 'Connect on launch';

  @override
  String get settingsKillSwitch => 'Block traffic without VPN';

  @override
  String get settingsKillSwitchIosCaption => 'Applies on the next connection.';

  @override
  String get settingsKillSwitchAndroidCaption =>
      'Opens the system VPN page. Turn on \"Always-on VPN\" and \"Block connections without VPN\" for Obsidian.';

  @override
  String get settingsSectionInterface => 'Interface';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLocaleSystem => 'System';

  @override
  String get settingsLocaleRu => 'Русский';

  @override
  String get settingsLocaleEn => 'English';

  @override
  String get settingsHaptics => 'Haptic feedback';

  @override
  String get settingsSectionDesktop => 'Computer';

  @override
  String get settingsAutostart => 'Start with the system';

  @override
  String get settingsMinimizeToTray => 'Minimize to tray on close';

  @override
  String get settingsMinimizeToTrayCaption =>
      'If off, closing the window quits the app.';

  @override
  String get settingsSectionDiagnostics => 'Diagnostics';

  @override
  String get settingsConnectionLog => 'Connection log';

  @override
  String get settingsDeviceId => 'Device ID';

  @override
  String get settingsDeviceIdCopied => 'Device ID copied';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsProtocol => 'Obsidian protocol v2, REALITY and UDP';

  @override
  String get logsClear => 'Clear';

  @override
  String get trayOpen => 'Open';

  @override
  String get trayConnect => 'Connect';

  @override
  String get trayDisconnect => 'Disconnect';

  @override
  String get trayQuit => 'Quit';
}
