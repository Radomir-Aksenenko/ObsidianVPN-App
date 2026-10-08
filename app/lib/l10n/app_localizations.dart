import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ru, this message translates to:
  /// **'Obsidian'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In ru, this message translates to:
  /// **'Главная'**
  String get navHome;

  /// No description provided for @navServers.
  ///
  /// In ru, this message translates to:
  /// **'Серверы'**
  String get navServers;

  /// No description provided for @navAccess.
  ///
  /// In ru, this message translates to:
  /// **'Доступ'**
  String get navAccess;

  /// No description provided for @navSettings.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get navSettings;

  /// No description provided for @windowMinimize.
  ///
  /// In ru, this message translates to:
  /// **'Свернуть'**
  String get windowMinimize;

  /// No description provided for @windowClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get windowClose;

  /// No description provided for @homeWordmark.
  ///
  /// In ru, this message translates to:
  /// **'obsidian'**
  String get homeWordmark;

  /// No description provided for @homeStatusDisconnected.
  ///
  /// In ru, this message translates to:
  /// **'ОТКЛЮЧЕНО'**
  String get homeStatusDisconnected;

  /// No description provided for @homeStatusConnecting.
  ///
  /// In ru, this message translates to:
  /// **'ПОДКЛЮЧЕНИЕ {stage}/4'**
  String homeStatusConnecting(int stage);

  /// No description provided for @homeStatusConnected.
  ///
  /// In ru, this message translates to:
  /// **'ЗАЩИЩЕНО'**
  String get homeStatusConnected;

  /// No description provided for @homeStatusReconnecting.
  ///
  /// In ru, this message translates to:
  /// **'ПЕРЕПОДКЛЮЧЕНИЕ'**
  String get homeStatusReconnecting;

  /// No description provided for @homeStatusDisconnecting.
  ///
  /// In ru, this message translates to:
  /// **'ОТКЛЮЧЕНИЕ'**
  String get homeStatusDisconnecting;

  /// No description provided for @homeStatusError.
  ///
  /// In ru, this message translates to:
  /// **'ОШИБКА'**
  String get homeStatusError;

  /// No description provided for @homeActionConnect.
  ///
  /// In ru, this message translates to:
  /// **'Подключить'**
  String get homeActionConnect;

  /// No description provided for @homeActionCancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get homeActionCancel;

  /// No description provided for @homeActionDisconnect.
  ///
  /// In ru, this message translates to:
  /// **'Отключить'**
  String get homeActionDisconnect;

  /// No description provided for @homeActionRetry.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get homeActionRetry;

  /// No description provided for @homeActionDisconnecting.
  ///
  /// In ru, this message translates to:
  /// **'Отключаем'**
  String get homeActionDisconnecting;

  /// No description provided for @homeLogs.
  ///
  /// In ru, this message translates to:
  /// **'Журнал'**
  String get homeLogs;

  /// No description provided for @logsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Журнал'**
  String get logsTitle;

  /// No description provided for @logsCopyAll.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать всё'**
  String get logsCopyAll;

  /// No description provided for @logsCopied.
  ///
  /// In ru, this message translates to:
  /// **'Журнал скопирован'**
  String get logsCopied;

  /// No description provided for @logsEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Записей пока нет'**
  String get logsEmpty;

  /// No description provided for @homeServerPickerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сервер'**
  String get homeServerPickerTitle;

  /// No description provided for @homeNoServers.
  ///
  /// In ru, this message translates to:
  /// **'Добавь первый сервер: вставь ключ доступа.'**
  String get homeNoServers;

  /// No description provided for @homeAddServer.
  ///
  /// In ru, this message translates to:
  /// **'Добавить сервер'**
  String get homeAddServer;

  /// No description provided for @homeSplitTitle.
  ///
  /// In ru, this message translates to:
  /// **'Раздельный туннель'**
  String get homeSplitTitle;

  /// No description provided for @trafficDownload.
  ///
  /// In ru, this message translates to:
  /// **'Загрузка'**
  String get trafficDownload;

  /// No description provided for @trafficUpload.
  ///
  /// In ru, this message translates to:
  /// **'Отдача'**
  String get trafficUpload;

  /// No description provided for @trafficTotal.
  ///
  /// In ru, this message translates to:
  /// **'Всего {value}'**
  String trafficTotal(String value);

  /// No description provided for @unitKbps.
  ///
  /// In ru, this message translates to:
  /// **'Кбит/с'**
  String get unitKbps;

  /// No description provided for @unitMbps.
  ///
  /// In ru, this message translates to:
  /// **'Мбит/с'**
  String get unitMbps;

  /// No description provided for @unitGbps.
  ///
  /// In ru, this message translates to:
  /// **'Гбит/с'**
  String get unitGbps;

  /// No description provided for @unitByte.
  ///
  /// In ru, this message translates to:
  /// **'Б'**
  String get unitByte;

  /// No description provided for @unitKilobyte.
  ///
  /// In ru, this message translates to:
  /// **'КБ'**
  String get unitKilobyte;

  /// No description provided for @unitMegabyte.
  ///
  /// In ru, this message translates to:
  /// **'МБ'**
  String get unitMegabyte;

  /// No description provided for @unitGigabyte.
  ///
  /// In ru, this message translates to:
  /// **'ГБ'**
  String get unitGigabyte;

  /// No description provided for @pingMs.
  ///
  /// In ru, this message translates to:
  /// **'{ms} мс'**
  String pingMs(int ms);

  /// No description provided for @pingNoReply.
  ///
  /// In ru, this message translates to:
  /// **'нет ответа'**
  String get pingNoReply;

  /// No description provided for @sheetClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get sheetClose;

  /// No description provided for @accessServers.
  ///
  /// In ru, this message translates to:
  /// **'Мои серверы'**
  String get accessServers;

  /// No description provided for @accessKeys.
  ///
  /// In ru, this message translates to:
  /// **'Выданные ключи'**
  String get accessKeys;

  /// No description provided for @accessDeploy.
  ///
  /// In ru, this message translates to:
  /// **'Развернуть сервер'**
  String get accessDeploy;

  /// No description provided for @accessIssue.
  ///
  /// In ru, this message translates to:
  /// **'Выдать ключ'**
  String get accessIssue;

  /// No description provided for @accessIssueNeedsServer.
  ///
  /// In ru, this message translates to:
  /// **'Чтобы выдать ключ, сначала разверни свой сервер.'**
  String get accessIssueNeedsServer;

  /// No description provided for @accessEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Obsidian ставится на чистый VPS с Ubuntu 22.04/24.04 или Debian 12, после этого с него выдаются ключи.'**
  String get accessEmpty;

  /// No description provided for @accessKeysEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Ключей пока нет. Выдай ключ, и он появится здесь.'**
  String get accessKeysEmpty;

  /// No description provided for @accessForever.
  ///
  /// In ru, this message translates to:
  /// **'Бессрочно'**
  String get accessForever;

  /// No description provided for @accessDaysLeft.
  ///
  /// In ru, this message translates to:
  /// **'Осталось {days} дн.'**
  String accessDaysLeft(int days);

  /// No description provided for @accessExpired.
  ///
  /// In ru, this message translates to:
  /// **'Срок истёк'**
  String get accessExpired;

  /// No description provided for @accessDevices.
  ///
  /// In ru, this message translates to:
  /// **'Устройств: {count}'**
  String accessDevices(int count);

  /// No description provided for @accessNeedsUpdate.
  ///
  /// In ru, this message translates to:
  /// **'Нужно обновить'**
  String get accessNeedsUpdate;

  /// No description provided for @accessKeyMore.
  ///
  /// In ru, this message translates to:
  /// **'Действия с ключом'**
  String get accessKeyMore;

  /// No description provided for @accessKeyDelete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить ключ'**
  String get accessKeyDelete;

  /// No description provided for @accessKeyDeleteTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить ключ?'**
  String get accessKeyDeleteTitle;

  /// No description provided for @accessKeyDeleteText.
  ///
  /// In ru, this message translates to:
  /// **'Ключ «{name}» пропадёт из списка. Отзыв ключей на сервере пока не поддерживается, поэтому он может работать до обнуления сервера.'**
  String accessKeyDeleteText(String name);

  /// No description provided for @accessKeyDeleted.
  ///
  /// In ru, this message translates to:
  /// **'Ключ удалён'**
  String get accessKeyDeleted;

  /// No description provided for @accessIssueTitle.
  ///
  /// In ru, this message translates to:
  /// **'Новый ключ'**
  String get accessIssueTitle;

  /// No description provided for @accessIssueName.
  ///
  /// In ru, this message translates to:
  /// **'Имя'**
  String get accessIssueName;

  /// No description provided for @accessIssueNameHint.
  ///
  /// In ru, this message translates to:
  /// **'Гость'**
  String get accessIssueNameHint;

  /// No description provided for @accessIssueValidity.
  ///
  /// In ru, this message translates to:
  /// **'Срок действия'**
  String get accessIssueValidity;

  /// No description provided for @accessValidity7.
  ///
  /// In ru, this message translates to:
  /// **'7 дней'**
  String get accessValidity7;

  /// No description provided for @accessValidity30.
  ///
  /// In ru, this message translates to:
  /// **'30 дней'**
  String get accessValidity30;

  /// No description provided for @accessValidity90.
  ///
  /// In ru, this message translates to:
  /// **'90 дней'**
  String get accessValidity90;

  /// No description provided for @accessIssueDevices.
  ///
  /// In ru, this message translates to:
  /// **'Устройств'**
  String get accessIssueDevices;

  /// No description provided for @accessFewer.
  ///
  /// In ru, this message translates to:
  /// **'Меньше'**
  String get accessFewer;

  /// No description provided for @accessMore.
  ///
  /// In ru, this message translates to:
  /// **'Больше'**
  String get accessMore;

  /// No description provided for @accessIssueServer.
  ///
  /// In ru, this message translates to:
  /// **'Сервер'**
  String get accessIssueServer;

  /// No description provided for @accessIssueSubmit.
  ///
  /// In ru, this message translates to:
  /// **'Выдать'**
  String get accessIssueSubmit;

  /// No description provided for @accessKeyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ключ'**
  String get accessKeyTitle;

  /// No description provided for @accessKeyServer.
  ///
  /// In ru, this message translates to:
  /// **'Сервер'**
  String get accessKeyServer;

  /// No description provided for @accessKeyExpiry.
  ///
  /// In ru, this message translates to:
  /// **'Срок действия'**
  String get accessKeyExpiry;

  /// No description provided for @accessKeyDevicesLabel.
  ///
  /// In ru, this message translates to:
  /// **'Устройств'**
  String get accessKeyDevicesLabel;

  /// No description provided for @accessKeyCopyLink.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать ссылку'**
  String get accessKeyCopyLink;

  /// No description provided for @accessKeyCopyKey.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать ключ'**
  String get accessKeyCopyKey;

  /// No description provided for @accessKeyShowKey.
  ///
  /// In ru, this message translates to:
  /// **'Показать ключ текстом'**
  String get accessKeyShowKey;

  /// No description provided for @accessKeyQrHint.
  ///
  /// In ru, this message translates to:
  /// **'Отсканируй QR-код в Obsidian на другом устройстве.'**
  String get accessKeyQrHint;

  /// No description provided for @accessKeyExpiresOn.
  ///
  /// In ru, this message translates to:
  /// **'До {date}'**
  String accessKeyExpiresOn(String date);

  /// No description provided for @accessCopied.
  ///
  /// In ru, this message translates to:
  /// **'Скопировано'**
  String get accessCopied;

  /// No description provided for @vpsDeployTitle.
  ///
  /// In ru, this message translates to:
  /// **'Развернуть сервер'**
  String get vpsDeployTitle;

  /// No description provided for @vpsDeployHint.
  ///
  /// In ru, this message translates to:
  /// **'Подойдёт чистый Ubuntu 22.04/24.04 или Debian 12. Пароль или ключ хранятся только на этом устройстве.'**
  String get vpsDeployHint;

  /// No description provided for @vpsHostLabel.
  ///
  /// In ru, this message translates to:
  /// **'IP или домен'**
  String get vpsHostLabel;

  /// No description provided for @vpsHostRequired.
  ///
  /// In ru, this message translates to:
  /// **'Укажи IP или домен.'**
  String get vpsHostRequired;

  /// No description provided for @vpsHostInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Адрес записан с ошибкой. Пример: 203.0.113.10 или vps.example.net'**
  String get vpsHostInvalid;

  /// No description provided for @vpsPortLabel.
  ///
  /// In ru, this message translates to:
  /// **'Порт SSH'**
  String get vpsPortLabel;

  /// No description provided for @vpsPortInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Порт от 1 до 65535.'**
  String get vpsPortInvalid;

  /// No description provided for @vpsUserLabel.
  ///
  /// In ru, this message translates to:
  /// **'Пользователь'**
  String get vpsUserLabel;

  /// No description provided for @vpsUserRequired.
  ///
  /// In ru, this message translates to:
  /// **'Укажи пользователя.'**
  String get vpsUserRequired;

  /// No description provided for @vpsAuthLabel.
  ///
  /// In ru, this message translates to:
  /// **'Вход'**
  String get vpsAuthLabel;

  /// No description provided for @vpsAuthPassword.
  ///
  /// In ru, this message translates to:
  /// **'Пароль'**
  String get vpsAuthPassword;

  /// No description provided for @vpsAuthKey.
  ///
  /// In ru, this message translates to:
  /// **'SSH-ключ'**
  String get vpsAuthKey;

  /// No description provided for @vpsPasswordLabel.
  ///
  /// In ru, this message translates to:
  /// **'Пароль'**
  String get vpsPasswordLabel;

  /// No description provided for @vpsPasswordRequired.
  ///
  /// In ru, this message translates to:
  /// **'Введи пароль.'**
  String get vpsPasswordRequired;

  /// No description provided for @vpsPasswordShow.
  ///
  /// In ru, this message translates to:
  /// **'Показать пароль'**
  String get vpsPasswordShow;

  /// No description provided for @vpsPasswordHide.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть пароль'**
  String get vpsPasswordHide;

  /// No description provided for @vpsKeyFile.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать файл ключа'**
  String get vpsKeyFile;

  /// No description provided for @vpsKeyFilePicked.
  ///
  /// In ru, this message translates to:
  /// **'Файл: {name}'**
  String vpsKeyFilePicked(String name);

  /// No description provided for @vpsKeyPasteLabel.
  ///
  /// In ru, this message translates to:
  /// **'Или вставь приватный ключ'**
  String get vpsKeyPasteLabel;

  /// No description provided for @vpsKeyRequired.
  ///
  /// In ru, this message translates to:
  /// **'Выбери файл или вставь приватный ключ.'**
  String get vpsKeyRequired;

  /// No description provided for @vpsKeyInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Это не похоже на приватный ключ. Нужен блок BEGIN ... PRIVATE KEY.'**
  String get vpsKeyInvalid;

  /// No description provided for @vpsPassphraseLabel.
  ///
  /// In ru, this message translates to:
  /// **'Пароль к ключу, если есть'**
  String get vpsPassphraseLabel;

  /// No description provided for @vpsSniLabel.
  ///
  /// In ru, this message translates to:
  /// **'Маскировка (SNI)'**
  String get vpsSniLabel;

  /// No description provided for @vpsSniCaption.
  ///
  /// In ru, this message translates to:
  /// **'Сайт, под который маскируется трафик. Клиенты используют тот же адрес.'**
  String get vpsSniCaption;

  /// No description provided for @vpsSniHint.
  ///
  /// In ru, this message translates to:
  /// **'Домен, например example.org'**
  String get vpsSniHint;

  /// No description provided for @vpsSniInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Укажи домен без https:// и пути.'**
  String get vpsSniInvalid;

  /// No description provided for @vpsDeployStart.
  ///
  /// In ru, this message translates to:
  /// **'Развернуть'**
  String get vpsDeployStart;

  /// No description provided for @vpsCancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get vpsCancel;

  /// No description provided for @vpsCancelDeployTitle.
  ///
  /// In ru, this message translates to:
  /// **'Прервать установку?'**
  String get vpsCancelDeployTitle;

  /// No description provided for @vpsCancelDeployText.
  ///
  /// In ru, this message translates to:
  /// **'Сервер останется в промежуточном состоянии. Чтобы продолжить, его придётся переустановить на чистом VPS.'**
  String get vpsCancelDeployText;

  /// No description provided for @vpsCancelDeployAction.
  ///
  /// In ru, this message translates to:
  /// **'Прервать'**
  String get vpsCancelDeployAction;

  /// No description provided for @vpsStay.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get vpsStay;

  /// No description provided for @vpsProgressTitle.
  ///
  /// In ru, this message translates to:
  /// **'Установка'**
  String get vpsProgressTitle;

  /// No description provided for @vpsSheetRunning.
  ///
  /// In ru, this message translates to:
  /// **'Не закрывай приложение до конца операции.'**
  String get vpsSheetRunning;

  /// No description provided for @vpsConsole.
  ///
  /// In ru, this message translates to:
  /// **'Журнал'**
  String get vpsConsole;

  /// No description provided for @vpsCopyLog.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать журнал'**
  String get vpsCopyLog;

  /// No description provided for @vpsLogCopied.
  ///
  /// In ru, this message translates to:
  /// **'Журнал скопирован'**
  String get vpsLogCopied;

  /// No description provided for @vpsRetry.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get vpsRetry;

  /// No description provided for @vpsFailed.
  ///
  /// In ru, this message translates to:
  /// **'Операция не выполнена'**
  String get vpsFailed;

  /// No description provided for @vpsSuccessTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сервер готов'**
  String get vpsSuccessTitle;

  /// No description provided for @vpsSuccessText.
  ///
  /// In ru, this message translates to:
  /// **'Владельческий ключ добавлен в Серверы и выбран. Им подключаешься сам.'**
  String get vpsSuccessText;

  /// No description provided for @vpsAdminToken.
  ///
  /// In ru, this message translates to:
  /// **'Токен администратора'**
  String get vpsAdminToken;

  /// No description provided for @vpsAdminTokenWarning.
  ///
  /// In ru, this message translates to:
  /// **'Сохрани его, второй раз не покажем. Он нужен для управления ключами на сервере.'**
  String get vpsAdminTokenWarning;

  /// No description provided for @vpsCopy.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать'**
  String get vpsCopy;

  /// No description provided for @vpsCopied.
  ///
  /// In ru, this message translates to:
  /// **'Скопировано'**
  String get vpsCopied;

  /// No description provided for @vpsDone.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get vpsDone;

  /// No description provided for @vpsHostKeyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ключ сервера изменился'**
  String get vpsHostKeyTitle;

  /// No description provided for @vpsHostKeyText.
  ///
  /// In ru, this message translates to:
  /// **'Отпечаток SSH-ключа сервера не совпадает с сохранённым. Так бывает после переустановки VPS, но это может быть и подмена сервера. Доверяй новому ключу, только если переустановил сервер сам.'**
  String get vpsHostKeyText;

  /// No description provided for @vpsHostKeyExpected.
  ///
  /// In ru, this message translates to:
  /// **'Ожидался'**
  String get vpsHostKeyExpected;

  /// No description provided for @vpsHostKeyActual.
  ///
  /// In ru, this message translates to:
  /// **'Получен'**
  String get vpsHostKeyActual;

  /// No description provided for @vpsHostKeyTrust.
  ///
  /// In ru, this message translates to:
  /// **'Доверять новому ключу'**
  String get vpsHostKeyTrust;

  /// No description provided for @vpsManageTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сервер'**
  String get vpsManageTitle;

  /// No description provided for @vpsBadgeReality.
  ///
  /// In ru, this message translates to:
  /// **'REALITY :{port}'**
  String vpsBadgeReality(int port);

  /// No description provided for @vpsBadgeIpv4.
  ///
  /// In ru, this message translates to:
  /// **'IPv4'**
  String get vpsBadgeIpv4;

  /// No description provided for @vpsBadgeDualStack.
  ///
  /// In ru, this message translates to:
  /// **'Dual-Stack'**
  String get vpsBadgeDualStack;

  /// No description provided for @vpsBadgeCreds.
  ///
  /// In ru, this message translates to:
  /// **'SSH сохранён'**
  String get vpsBadgeCreds;

  /// No description provided for @vpsNoCreds.
  ///
  /// In ru, this message translates to:
  /// **'Доступ по SSH не сохранён. Без него нельзя обновить ядро и менять настройки.'**
  String get vpsNoCreds;

  /// No description provided for @vpsAddCreds.
  ///
  /// In ru, this message translates to:
  /// **'Добавить доступ'**
  String get vpsAddCreds;

  /// No description provided for @vpsSniSection.
  ///
  /// In ru, this message translates to:
  /// **'Маскировка (SNI)'**
  String get vpsSniSection;

  /// No description provided for @vpsSniApply.
  ///
  /// In ru, this message translates to:
  /// **'Применить новый SNI'**
  String get vpsSniApply;

  /// No description provided for @vpsReissueNote.
  ///
  /// In ru, this message translates to:
  /// **'Владельческий ключ пересоберётся. Ранее выданные ключи нужно выдать заново: в них записаны старые настройки.'**
  String get vpsReissueNote;

  /// No description provided for @vpsSniDone.
  ///
  /// In ru, this message translates to:
  /// **'SNI применён'**
  String get vpsSniDone;

  /// No description provided for @vpsIpv6Section.
  ///
  /// In ru, this message translates to:
  /// **'IPv6'**
  String get vpsIpv6Section;

  /// No description provided for @vpsIpv6Done.
  ///
  /// In ru, this message translates to:
  /// **'Настройка IPv6 сохранена'**
  String get vpsIpv6Done;

  /// No description provided for @vpsCoreSection.
  ///
  /// In ru, this message translates to:
  /// **'Ядро'**
  String get vpsCoreSection;

  /// No description provided for @vpsCoreVersion.
  ///
  /// In ru, this message translates to:
  /// **'Версия {version}'**
  String vpsCoreVersion(String version);

  /// No description provided for @vpsUpdateNeeded.
  ///
  /// In ru, this message translates to:
  /// **'Требуется обновление'**
  String get vpsUpdateNeeded;

  /// No description provided for @vpsUpToDate.
  ///
  /// In ru, this message translates to:
  /// **'Актуально'**
  String get vpsUpToDate;

  /// No description provided for @vpsCheckUpdates.
  ///
  /// In ru, this message translates to:
  /// **'Проверить обновления'**
  String get vpsCheckUpdates;

  /// No description provided for @vpsUpdate.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get vpsUpdate;

  /// No description provided for @vpsUpdateDone.
  ///
  /// In ru, this message translates to:
  /// **'Ядро обновлено'**
  String get vpsUpdateDone;

  /// No description provided for @vpsCheckLatest.
  ///
  /// In ru, this message translates to:
  /// **'Установлена актуальная версия ядра.'**
  String get vpsCheckLatest;

  /// No description provided for @vpsCheckOutdated.
  ///
  /// In ru, this message translates to:
  /// **'Доступна новая версия ядра.'**
  String get vpsCheckOutdated;

  /// No description provided for @vpsSshSection.
  ///
  /// In ru, this message translates to:
  /// **'Доступ по SSH'**
  String get vpsSshSection;

  /// No description provided for @vpsEditSsh.
  ///
  /// In ru, this message translates to:
  /// **'Изменить доступ'**
  String get vpsEditSsh;

  /// No description provided for @vpsSaveSsh.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get vpsSaveSsh;

  /// No description provided for @vpsSshSaved.
  ///
  /// In ru, this message translates to:
  /// **'Доступ сохранён'**
  String get vpsSshSaved;

  /// No description provided for @vpsResetAction.
  ///
  /// In ru, this message translates to:
  /// **'Обнулить сервер'**
  String get vpsResetAction;

  /// No description provided for @vpsResetTitle.
  ///
  /// In ru, this message translates to:
  /// **'Обнулить сервер?'**
  String get vpsResetTitle;

  /// No description provided for @vpsResetText.
  ///
  /// In ru, this message translates to:
  /// **'Все ключи, выданные с этого сервера, перестанут работать. Сервер получит новые ключи, владельческий ключ пересоберётся.'**
  String get vpsResetText;

  /// No description provided for @vpsResetConfirm.
  ///
  /// In ru, this message translates to:
  /// **'Обнулить'**
  String get vpsResetConfirm;

  /// No description provided for @vpsResetDone.
  ///
  /// In ru, this message translates to:
  /// **'Сервер обнулён, владельческий ключ обновлён'**
  String get vpsResetDone;

  /// No description provided for @vpsSheetCheck.
  ///
  /// In ru, this message translates to:
  /// **'Проверка версии'**
  String get vpsSheetCheck;

  /// No description provided for @vpsSheetSni.
  ///
  /// In ru, this message translates to:
  /// **'Смена SNI'**
  String get vpsSheetSni;

  /// No description provided for @vpsSheetUpdate.
  ///
  /// In ru, this message translates to:
  /// **'Обновление ядра'**
  String get vpsSheetUpdate;

  /// No description provided for @vpsSheetIpv6.
  ///
  /// In ru, this message translates to:
  /// **'Настройка IPv6'**
  String get vpsSheetIpv6;

  /// No description provided for @vpsSheetReset.
  ///
  /// In ru, this message translates to:
  /// **'Обнуление сервера'**
  String get vpsSheetReset;

  /// No description provided for @vpsErrorGeneric.
  ///
  /// In ru, this message translates to:
  /// **'Что-то пошло не так. Попробуй ещё раз.'**
  String get vpsErrorGeneric;

  /// No description provided for @vpsOwnerKeyMissing.
  ///
  /// In ru, this message translates to:
  /// **'Владельческий ключ не найден на этом устройстве. Переустанови сервер, чтобы создать его заново.'**
  String get vpsOwnerKeyMissing;

  /// No description provided for @serversTitle.
  ///
  /// In ru, this message translates to:
  /// **'Серверы'**
  String get serversTitle;

  /// No description provided for @serversSectionFavorites.
  ///
  /// In ru, this message translates to:
  /// **'Избранное'**
  String get serversSectionFavorites;

  /// No description provided for @serversSectionAll.
  ///
  /// In ru, this message translates to:
  /// **'Все серверы'**
  String get serversSectionAll;

  /// No description provided for @serversAddKey.
  ///
  /// In ru, this message translates to:
  /// **'Добавить ключ'**
  String get serversAddKey;

  /// No description provided for @serversScanQr.
  ///
  /// In ru, this message translates to:
  /// **'Сканировать QR'**
  String get serversScanQr;

  /// No description provided for @serversEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Добавь первый сервер: вставь ключ доступа.'**
  String get serversEmpty;

  /// No description provided for @serversMore.
  ///
  /// In ru, this message translates to:
  /// **'Действия'**
  String get serversMore;

  /// No description provided for @serversActionRename.
  ///
  /// In ru, this message translates to:
  /// **'Переименовать'**
  String get serversActionRename;

  /// No description provided for @serversActionFavoriteAdd.
  ///
  /// In ru, this message translates to:
  /// **'В избранное'**
  String get serversActionFavoriteAdd;

  /// No description provided for @serversActionFavoriteRemove.
  ///
  /// In ru, this message translates to:
  /// **'Убрать из избранного'**
  String get serversActionFavoriteRemove;

  /// No description provided for @serversActionSplit.
  ///
  /// In ru, this message translates to:
  /// **'Раздельный туннель'**
  String get serversActionSplit;

  /// No description provided for @serversActionDelete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get serversActionDelete;

  /// No description provided for @serversRenameTitle.
  ///
  /// In ru, this message translates to:
  /// **'Новое название'**
  String get serversRenameTitle;

  /// No description provided for @serversNameLabel.
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get serversNameLabel;

  /// No description provided for @serversNameHint.
  ///
  /// In ru, this message translates to:
  /// **'Например, Франкфурт'**
  String get serversNameHint;

  /// No description provided for @serversSave.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get serversSave;

  /// No description provided for @serversRenamed.
  ///
  /// In ru, this message translates to:
  /// **'Название сохранено'**
  String get serversRenamed;

  /// No description provided for @serversFavoriteAdded.
  ///
  /// In ru, this message translates to:
  /// **'Добавлен в избранное'**
  String get serversFavoriteAdded;

  /// No description provided for @serversFavoriteRemoved.
  ///
  /// In ru, this message translates to:
  /// **'Убран из избранного'**
  String get serversFavoriteRemoved;

  /// No description provided for @serversDeleteTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить сервер?'**
  String get serversDeleteTitle;

  /// No description provided for @serversDeleteBody.
  ///
  /// In ru, this message translates to:
  /// **'Ключ этого сервера удалится с устройства. Вернуть сервер можно, только вставив ключ заново.'**
  String get serversDeleteBody;

  /// No description provided for @serversDeleteConfirm.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get serversDeleteConfirm;

  /// No description provided for @serversCancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get serversCancel;

  /// No description provided for @serversDeleted.
  ///
  /// In ru, this message translates to:
  /// **'Сервер удалён'**
  String get serversDeleted;

  /// No description provided for @serversDeleteBlocked.
  ///
  /// In ru, this message translates to:
  /// **'Сначала отключись от этого сервера.'**
  String get serversDeleteBlocked;

  /// No description provided for @serversAdded.
  ///
  /// In ru, this message translates to:
  /// **'Сервер добавлен'**
  String get serversAdded;

  /// No description provided for @serversAddFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить сервер. Попробуй ещё раз.'**
  String get serversAddFailed;

  /// No description provided for @serversClipboardEmpty.
  ///
  /// In ru, this message translates to:
  /// **'В буфере обмена нет текста.'**
  String get serversClipboardEmpty;

  /// No description provided for @addKeyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Добавить ключ'**
  String get addKeyTitle;

  /// No description provided for @addKeyField.
  ///
  /// In ru, this message translates to:
  /// **'Ключ доступа'**
  String get addKeyField;

  /// No description provided for @addKeyFieldHint.
  ///
  /// In ru, this message translates to:
  /// **'Вставь ключ или ссылку obsidian://'**
  String get addKeyFieldHint;

  /// No description provided for @addKeyPaste.
  ///
  /// In ru, this message translates to:
  /// **'Вставить'**
  String get addKeyPaste;

  /// No description provided for @addKeyNameField.
  ///
  /// In ru, this message translates to:
  /// **'Название, необязательно'**
  String get addKeyNameField;

  /// No description provided for @addKeyNameHint.
  ///
  /// In ru, this message translates to:
  /// **'Например, Франкфурт'**
  String get addKeyNameHint;

  /// No description provided for @addKeyRecognized.
  ///
  /// In ru, this message translates to:
  /// **'Распознано: {hostPort}'**
  String addKeyRecognized(String hostPort);

  /// No description provided for @addKeySubmit.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get addKeySubmit;

  /// No description provided for @qrTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сканировать QR'**
  String get qrTitle;

  /// No description provided for @qrHint.
  ///
  /// In ru, this message translates to:
  /// **'Наведи камеру на QR-код ключа'**
  String get qrHint;

  /// No description provided for @qrTorch.
  ///
  /// In ru, this message translates to:
  /// **'Фонарик'**
  String get qrTorch;

  /// No description provided for @qrDeniedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступа к камере'**
  String get qrDeniedTitle;

  /// No description provided for @qrDeniedBody.
  ///
  /// In ru, this message translates to:
  /// **'Разреши доступ к камере в настройках системы, чтобы сканировать ключ. Или вставь ключ вручную.'**
  String get qrDeniedBody;

  /// No description provided for @qrError.
  ///
  /// In ru, this message translates to:
  /// **'Камера недоступна. Вставь ключ вручную.'**
  String get qrError;

  /// No description provided for @splitTitle.
  ///
  /// In ru, this message translates to:
  /// **'Раздельный туннель'**
  String get splitTitle;

  /// No description provided for @splitModeOff.
  ///
  /// In ru, this message translates to:
  /// **'Выкл'**
  String get splitModeOff;

  /// No description provided for @splitModeInclude.
  ///
  /// In ru, this message translates to:
  /// **'Только список'**
  String get splitModeInclude;

  /// No description provided for @splitModeExclude.
  ///
  /// In ru, this message translates to:
  /// **'Кроме списка'**
  String get splitModeExclude;

  /// No description provided for @splitOffNote.
  ///
  /// In ru, this message translates to:
  /// **'Весь трафик идет через VPN. Список ниже сохранится.'**
  String get splitOffNote;

  /// No description provided for @splitPresets.
  ///
  /// In ru, this message translates to:
  /// **'Готовые наборы'**
  String get splitPresets;

  /// No description provided for @splitPresetCount.
  ///
  /// In ru, this message translates to:
  /// **'Адресов в наборе: {count}'**
  String splitPresetCount(int count);

  /// No description provided for @splitEntries.
  ///
  /// In ru, this message translates to:
  /// **'Свои правила'**
  String get splitEntries;

  /// No description provided for @splitEntriesHint.
  ///
  /// In ru, this message translates to:
  /// **'Домен, IP или подсеть в каждой строке'**
  String get splitEntriesHint;

  /// No description provided for @splitAccepted.
  ///
  /// In ru, this message translates to:
  /// **'Принято правил: {count}'**
  String splitAccepted(int count);

  /// No description provided for @splitIssues.
  ///
  /// In ru, this message translates to:
  /// **'Не распознано'**
  String get splitIssues;

  /// No description provided for @splitEmptyWarning.
  ///
  /// In ru, this message translates to:
  /// **'Список пуст: через VPN сейчас ничего не идет.'**
  String get splitEmptyWarning;

  /// No description provided for @splitNoteDomains.
  ///
  /// In ru, this message translates to:
  /// **'Домены повторно резолвятся каждые 10 минут.'**
  String get splitNoteDomains;

  /// No description provided for @splitNoteWildcards.
  ///
  /// In ru, this message translates to:
  /// **'Маски вроде *.ru не поддерживаются: укажи конкретный домен.'**
  String get splitNoteWildcards;

  /// No description provided for @splitNoteIdn.
  ///
  /// In ru, this message translates to:
  /// **'Кириллические домены записывай в punycode, с префиксом xn--.'**
  String get splitNoteIdn;

  /// No description provided for @splitSave.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get splitSave;

  /// No description provided for @splitSaved.
  ///
  /// In ru, this message translates to:
  /// **'Правила сохранены'**
  String get splitSaved;

  /// No description provided for @splitSavedSkipped.
  ///
  /// In ru, this message translates to:
  /// **'Правила сохранены. Пропущено строк: {count}'**
  String splitSavedSkipped(int count);

  /// No description provided for @splitLiveNote.
  ///
  /// In ru, this message translates to:
  /// **'Изменения сразу применятся к текущему подключению.'**
  String get splitLiveNote;

  /// No description provided for @splitUnsavedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить изменения?'**
  String get splitUnsavedTitle;

  /// No description provided for @splitUnsavedBody.
  ///
  /// In ru, this message translates to:
  /// **'Раздельный туннель изменён, но не сохранён.'**
  String get splitUnsavedBody;

  /// No description provided for @splitDiscard.
  ///
  /// In ru, this message translates to:
  /// **'Не сохранять'**
  String get splitDiscard;

  /// No description provided for @splitKeepEditing.
  ///
  /// In ru, this message translates to:
  /// **'Остаться'**
  String get splitKeepEditing;

  /// No description provided for @splitMissing.
  ///
  /// In ru, this message translates to:
  /// **'Сервер не найден.'**
  String get splitMissing;

  /// No description provided for @settingsSectionConnection.
  ///
  /// In ru, this message translates to:
  /// **'Подключение'**
  String get settingsSectionConnection;

  /// No description provided for @settingsAutoConnect.
  ///
  /// In ru, this message translates to:
  /// **'Подключаться при запуске'**
  String get settingsAutoConnect;

  /// No description provided for @settingsKillSwitch.
  ///
  /// In ru, this message translates to:
  /// **'Блокировать трафик без VPN'**
  String get settingsKillSwitch;

  /// No description provided for @settingsKillSwitchIosCaption.
  ///
  /// In ru, this message translates to:
  /// **'Применяется при следующем подключении.'**
  String get settingsKillSwitchIosCaption;

  /// No description provided for @settingsKillSwitchAndroidCaption.
  ///
  /// In ru, this message translates to:
  /// **'Откроется системный раздел VPN. Включи «Постоянная VPN» и «Блокировать соединения без VPN» для Obsidian.'**
  String get settingsKillSwitchAndroidCaption;

  /// No description provided for @settingsSectionInterface.
  ///
  /// In ru, this message translates to:
  /// **'Интерфейс'**
  String get settingsSectionInterface;

  /// No description provided for @settingsTheme.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In ru, this message translates to:
  /// **'Системная'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get settingsThemeLight;

  /// No description provided for @settingsLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get settingsLanguage;

  /// No description provided for @settingsLocaleSystem.
  ///
  /// In ru, this message translates to:
  /// **'Системный'**
  String get settingsLocaleSystem;

  /// No description provided for @settingsLocaleRu.
  ///
  /// In ru, this message translates to:
  /// **'Русский'**
  String get settingsLocaleRu;

  /// No description provided for @settingsLocaleEn.
  ///
  /// In ru, this message translates to:
  /// **'English'**
  String get settingsLocaleEn;

  /// No description provided for @settingsHaptics.
  ///
  /// In ru, this message translates to:
  /// **'Тактильный отклик'**
  String get settingsHaptics;

  /// No description provided for @settingsSectionDesktop.
  ///
  /// In ru, this message translates to:
  /// **'Компьютер'**
  String get settingsSectionDesktop;

  /// No description provided for @settingsAutostart.
  ///
  /// In ru, this message translates to:
  /// **'Запускать вместе с системой'**
  String get settingsAutostart;

  /// No description provided for @settingsMinimizeToTray.
  ///
  /// In ru, this message translates to:
  /// **'Сворачивать в трей при закрытии'**
  String get settingsMinimizeToTray;

  /// No description provided for @settingsMinimizeToTrayCaption.
  ///
  /// In ru, this message translates to:
  /// **'Если выключено, закрытие окна завершает приложение.'**
  String get settingsMinimizeToTrayCaption;

  /// No description provided for @settingsSectionDiagnostics.
  ///
  /// In ru, this message translates to:
  /// **'Диагностика'**
  String get settingsSectionDiagnostics;

  /// No description provided for @settingsConnectionLog.
  ///
  /// In ru, this message translates to:
  /// **'Журнал подключения'**
  String get settingsConnectionLog;

  /// No description provided for @settingsDeviceId.
  ///
  /// In ru, this message translates to:
  /// **'ID устройства'**
  String get settingsDeviceId;

  /// No description provided for @settingsDeviceIdCopied.
  ///
  /// In ru, this message translates to:
  /// **'ID устройства скопирован'**
  String get settingsDeviceIdCopied;

  /// No description provided for @settingsSectionAbout.
  ///
  /// In ru, this message translates to:
  /// **'О приложении'**
  String get settingsSectionAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In ru, this message translates to:
  /// **'Версия'**
  String get settingsVersion;

  /// No description provided for @settingsProtocol.
  ///
  /// In ru, this message translates to:
  /// **'Протокол Obsidian v2, REALITY и UDP'**
  String get settingsProtocol;

  /// No description provided for @logsClear.
  ///
  /// In ru, this message translates to:
  /// **'Очистить'**
  String get logsClear;

  /// No description provided for @trayOpen.
  ///
  /// In ru, this message translates to:
  /// **'Открыть'**
  String get trayOpen;

  /// No description provided for @trayConnect.
  ///
  /// In ru, this message translates to:
  /// **'Подключить'**
  String get trayConnect;

  /// No description provided for @trayDisconnect.
  ///
  /// In ru, this message translates to:
  /// **'Отключить'**
  String get trayDisconnect;

  /// No description provided for @trayQuit.
  ///
  /// In ru, this message translates to:
  /// **'Выйти'**
  String get trayQuit;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
