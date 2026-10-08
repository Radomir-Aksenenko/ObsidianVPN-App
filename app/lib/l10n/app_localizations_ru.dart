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

  @override
  String get homeWordmark => 'obsidian';

  @override
  String get homeStatusDisconnected => 'ОТКЛЮЧЕНО';

  @override
  String homeStatusConnecting(int stage) {
    return 'ПОДКЛЮЧЕНИЕ $stage/4';
  }

  @override
  String get homeStatusConnected => 'ЗАЩИЩЕНО';

  @override
  String get homeStatusReconnecting => 'ПЕРЕПОДКЛЮЧЕНИЕ';

  @override
  String get homeStatusDisconnecting => 'ОТКЛЮЧЕНИЕ';

  @override
  String get homeStatusError => 'ОШИБКА';

  @override
  String get homeActionConnect => 'Подключить';

  @override
  String get homeActionCancel => 'Отмена';

  @override
  String get homeActionDisconnect => 'Отключить';

  @override
  String get homeActionRetry => 'Повторить';

  @override
  String get homeActionDisconnecting => 'Отключаем';

  @override
  String get homeLogs => 'Журнал';

  @override
  String get logsTitle => 'Журнал';

  @override
  String get logsCopyAll => 'Скопировать всё';

  @override
  String get logsCopied => 'Журнал скопирован';

  @override
  String get logsEmpty => 'Записей пока нет';

  @override
  String get homeServerPickerTitle => 'Сервер';

  @override
  String get homeNoServers => 'Добавь первый сервер: вставь ключ доступа.';

  @override
  String get homeAddServer => 'Добавить сервер';

  @override
  String get homeSplitTitle => 'Раздельный туннель';

  @override
  String get trafficDownload => 'Загрузка';

  @override
  String get trafficUpload => 'Отдача';

  @override
  String trafficTotal(String value) {
    return 'Всего $value';
  }

  @override
  String get unitKbps => 'Кбит/с';

  @override
  String get unitMbps => 'Мбит/с';

  @override
  String get unitGbps => 'Гбит/с';

  @override
  String get unitByte => 'Б';

  @override
  String get unitKilobyte => 'КБ';

  @override
  String get unitMegabyte => 'МБ';

  @override
  String get unitGigabyte => 'ГБ';

  @override
  String pingMs(int ms) {
    return '$ms мс';
  }

  @override
  String get pingNoReply => 'нет ответа';

  @override
  String get sheetClose => 'Закрыть';
}
