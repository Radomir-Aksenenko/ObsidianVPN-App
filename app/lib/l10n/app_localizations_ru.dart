// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Obsidian';

  @override
  String get navHome => 'Главная';

  @override
  String get navServers => 'Серверы';

  @override
  String get navAccess => 'Доступ';

  @override
  String get navSettings => 'Настройки';

  @override
  String get windowMinimize => 'Свернуть';

  @override
  String get windowClose => 'Закрыть';
}
