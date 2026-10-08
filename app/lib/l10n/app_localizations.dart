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
