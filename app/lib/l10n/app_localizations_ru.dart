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

  @override
  String get accessServers => 'Мои серверы';

  @override
  String get accessKeys => 'Выданные ключи';

  @override
  String get accessDeploy => 'Развернуть сервер';

  @override
  String get accessIssue => 'Выдать ключ';

  @override
  String get accessIssueNeedsServer =>
      'Чтобы выдать ключ, сначала разверни свой сервер.';

  @override
  String get accessEmpty =>
      'Obsidian ставится на чистый VPS с Ubuntu 22.04/24.04 или Debian 12, после этого с него выдаются ключи.';

  @override
  String get accessKeysEmpty =>
      'Ключей пока нет. Выдай ключ, и он появится здесь.';

  @override
  String get accessForever => 'Бессрочно';

  @override
  String accessDaysLeft(int days) {
    return 'Осталось $days дн.';
  }

  @override
  String get accessExpired => 'Срок истёк';

  @override
  String accessDevices(int count) {
    return 'Устройств: $count';
  }

  @override
  String get accessNeedsUpdate => 'Нужно обновить';

  @override
  String get accessKeyMore => 'Действия с ключом';

  @override
  String get accessKeyDelete => 'Удалить ключ';

  @override
  String get accessKeyDeleteTitle => 'Удалить ключ?';

  @override
  String accessKeyDeleteText(String name) {
    return 'Ключ «$name» пропадёт из списка. Отзыв ключей на сервере пока не поддерживается, поэтому он может работать до обнуления сервера.';
  }

  @override
  String get accessKeyDeleted => 'Ключ удалён';

  @override
  String get accessIssueTitle => 'Новый ключ';

  @override
  String get accessIssueName => 'Имя';

  @override
  String get accessIssueNameHint => 'Гость';

  @override
  String get accessIssueValidity => 'Срок действия';

  @override
  String get accessValidity7 => '7 дней';

  @override
  String get accessValidity30 => '30 дней';

  @override
  String get accessValidity90 => '90 дней';

  @override
  String get accessIssueDevices => 'Устройств';

  @override
  String get accessFewer => 'Меньше';

  @override
  String get accessMore => 'Больше';

  @override
  String get accessIssueServer => 'Сервер';

  @override
  String get accessIssueSubmit => 'Выдать';

  @override
  String get accessKeyTitle => 'Ключ';

  @override
  String get accessKeyServer => 'Сервер';

  @override
  String get accessKeyExpiry => 'Срок действия';

  @override
  String get accessKeyDevicesLabel => 'Устройств';

  @override
  String get accessKeyCopyLink => 'Скопировать ссылку';

  @override
  String get accessKeyCopyKey => 'Скопировать ключ';

  @override
  String get accessKeyShowKey => 'Показать ключ текстом';

  @override
  String get accessKeyQrHint =>
      'Отсканируй QR-код в Obsidian на другом устройстве.';

  @override
  String accessKeyExpiresOn(String date) {
    return 'До $date';
  }

  @override
  String get accessCopied => 'Скопировано';

  @override
  String get vpsDeployTitle => 'Развернуть сервер';

  @override
  String get vpsDeployHint =>
      'Подойдёт чистый Ubuntu 22.04/24.04 или Debian 12. Пароль или ключ хранятся только на этом устройстве.';

  @override
  String get vpsHostLabel => 'IP или домен';

  @override
  String get vpsHostRequired => 'Укажи IP или домен.';

  @override
  String get vpsHostInvalid =>
      'Адрес записан с ошибкой. Пример: 203.0.113.10 или vps.example.net';

  @override
  String get vpsPortLabel => 'Порт SSH';

  @override
  String get vpsPortInvalid => 'Порт от 1 до 65535.';

  @override
  String get vpsUserLabel => 'Пользователь';

  @override
  String get vpsUserRequired => 'Укажи пользователя.';

  @override
  String get vpsAuthLabel => 'Вход';

  @override
  String get vpsAuthPassword => 'Пароль';

  @override
  String get vpsAuthKey => 'SSH-ключ';

  @override
  String get vpsPasswordLabel => 'Пароль';

  @override
  String get vpsPasswordRequired => 'Введи пароль.';

  @override
  String get vpsPasswordShow => 'Показать пароль';

  @override
  String get vpsPasswordHide => 'Скрыть пароль';

  @override
  String get vpsKeyFile => 'Выбрать файл ключа';

  @override
  String vpsKeyFilePicked(String name) {
    return 'Файл: $name';
  }

  @override
  String get vpsKeyPasteLabel => 'Или вставь приватный ключ';

  @override
  String get vpsKeyRequired => 'Выбери файл или вставь приватный ключ.';

  @override
  String get vpsKeyInvalid =>
      'Это не похоже на приватный ключ. Нужен блок BEGIN ... PRIVATE KEY.';

  @override
  String get vpsPassphraseLabel => 'Пароль к ключу, если есть';

  @override
  String get vpsSniLabel => 'Маскировка (SNI)';

  @override
  String get vpsSniCaption =>
      'Сайт, под который маскируется трафик. Клиенты используют тот же адрес.';

  @override
  String get vpsSniHint => 'Домен, например example.org';

  @override
  String get vpsSniInvalid => 'Укажи домен без https:// и пути.';

  @override
  String get vpsDeployStart => 'Развернуть';

  @override
  String get vpsCancel => 'Отмена';

  @override
  String get vpsCancelDeployTitle => 'Прервать установку?';

  @override
  String get vpsCancelDeployText =>
      'Сервер останется в промежуточном состоянии. Чтобы продолжить, его придётся переустановить на чистом VPS.';

  @override
  String get vpsCancelDeployAction => 'Прервать';

  @override
  String get vpsStay => 'Продолжить';

  @override
  String get vpsProgressTitle => 'Установка';

  @override
  String get vpsSheetRunning => 'Не закрывай приложение до конца операции.';

  @override
  String get vpsConsole => 'Журнал';

  @override
  String get vpsCopyLog => 'Скопировать журнал';

  @override
  String get vpsLogCopied => 'Журнал скопирован';

  @override
  String get vpsRetry => 'Повторить';

  @override
  String get vpsFailed => 'Операция не выполнена';

  @override
  String get vpsSuccessTitle => 'Сервер готов';

  @override
  String get vpsSuccessText =>
      'Владельческий ключ добавлен в Серверы и выбран. Им подключаешься сам.';

  @override
  String get vpsAdminToken => 'Токен администратора';

  @override
  String get vpsAdminTokenWarning =>
      'Сохрани его, второй раз не покажем. Он нужен для управления ключами на сервере.';

  @override
  String get vpsCopy => 'Скопировать';

  @override
  String get vpsCopied => 'Скопировано';

  @override
  String get vpsDone => 'Готово';

  @override
  String get vpsHostKeyTitle => 'Ключ сервера изменился';

  @override
  String get vpsHostKeyText =>
      'Отпечаток SSH-ключа сервера не совпадает с сохранённым. Так бывает после переустановки VPS, но это может быть и подмена сервера. Доверяй новому ключу, только если переустановил сервер сам.';

  @override
  String get vpsHostKeyExpected => 'Ожидался';

  @override
  String get vpsHostKeyActual => 'Получен';

  @override
  String get vpsHostKeyTrust => 'Доверять новому ключу';

  @override
  String get vpsManageTitle => 'Сервер';

  @override
  String vpsBadgeReality(int port) {
    return 'REALITY :$port';
  }

  @override
  String get vpsBadgeIpv4 => 'IPv4';

  @override
  String get vpsBadgeDualStack => 'Dual-Stack';

  @override
  String get vpsBadgeCreds => 'SSH сохранён';

  @override
  String get vpsNoCreds =>
      'Доступ по SSH не сохранён. Без него нельзя обновить ядро и менять настройки.';

  @override
  String get vpsAddCreds => 'Добавить доступ';

  @override
  String get vpsSniSection => 'Маскировка (SNI)';

  @override
  String get vpsSniApply => 'Применить новый SNI';

  @override
  String get vpsReissueNote =>
      'Владельческий ключ пересоберётся. Ранее выданные ключи нужно выдать заново: в них записаны старые настройки.';

  @override
  String get vpsSniDone => 'SNI применён';

  @override
  String get vpsIpv6Section => 'IPv6';

  @override
  String get vpsIpv6Done => 'Настройка IPv6 сохранена';

  @override
  String get vpsCoreSection => 'Ядро';

  @override
  String vpsCoreVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get vpsUpdateNeeded => 'Требуется обновление';

  @override
  String get vpsUpToDate => 'Актуально';

  @override
  String get vpsCheckUpdates => 'Проверить обновления';

  @override
  String get vpsUpdate => 'Обновить';

  @override
  String get vpsUpdateDone => 'Ядро обновлено';

  @override
  String get vpsCheckLatest => 'Установлена актуальная версия ядра.';

  @override
  String get vpsCheckOutdated => 'Доступна новая версия ядра.';

  @override
  String get vpsSshSection => 'Доступ по SSH';

  @override
  String get vpsEditSsh => 'Изменить доступ';

  @override
  String get vpsSaveSsh => 'Сохранить';

  @override
  String get vpsSshSaved => 'Доступ сохранён';

  @override
  String get vpsResetAction => 'Обнулить сервер';

  @override
  String get vpsResetTitle => 'Обнулить сервер?';

  @override
  String get vpsResetText =>
      'Все ключи, выданные с этого сервера, перестанут работать. Сервер получит новые ключи, владельческий ключ пересоберётся.';

  @override
  String get vpsResetConfirm => 'Обнулить';

  @override
  String get vpsResetDone => 'Сервер обнулён, владельческий ключ обновлён';

  @override
  String get vpsSheetCheck => 'Проверка версии';

  @override
  String get vpsSheetSni => 'Смена SNI';

  @override
  String get vpsSheetUpdate => 'Обновление ядра';

  @override
  String get vpsSheetIpv6 => 'Настройка IPv6';

  @override
  String get vpsSheetReset => 'Обнуление сервера';

  @override
  String get vpsErrorGeneric => 'Что-то пошло не так. Попробуй ещё раз.';

  @override
  String get vpsOwnerKeyMissing =>
      'Владельческий ключ не найден на этом устройстве. Переустанови сервер, чтобы создать его заново.';

  @override
  String get serversTitle => 'Серверы';

  @override
  String get serversSectionFavorites => 'Избранное';

  @override
  String get serversSectionAll => 'Все серверы';

  @override
  String get serversAddKey => 'Добавить ключ';

  @override
  String get serversScanQr => 'Сканировать QR';

  @override
  String get serversEmpty => 'Добавь первый сервер: вставь ключ доступа.';

  @override
  String get serversMore => 'Действия';

  @override
  String get serversActionRename => 'Переименовать';

  @override
  String get serversActionFavoriteAdd => 'В избранное';

  @override
  String get serversActionFavoriteRemove => 'Убрать из избранного';

  @override
  String get serversActionSplit => 'Раздельный туннель';

  @override
  String get serversActionDelete => 'Удалить';

  @override
  String get serversRenameTitle => 'Новое название';

  @override
  String get serversNameLabel => 'Название';

  @override
  String get serversNameHint => 'Например, Франкфурт';

  @override
  String get serversSave => 'Сохранить';

  @override
  String get serversRenamed => 'Название сохранено';

  @override
  String get serversFavoriteAdded => 'Добавлен в избранное';

  @override
  String get serversFavoriteRemoved => 'Убран из избранного';

  @override
  String get serversDeleteTitle => 'Удалить сервер?';

  @override
  String get serversDeleteBody =>
      'Ключ этого сервера удалится с устройства. Вернуть сервер можно, только вставив ключ заново.';

  @override
  String get serversDeleteConfirm => 'Удалить';

  @override
  String get serversCancel => 'Отмена';

  @override
  String get serversDeleted => 'Сервер удалён';

  @override
  String get serversDeleteBlocked => 'Сначала отключись от этого сервера.';

  @override
  String get serversAdded => 'Сервер добавлен';

  @override
  String get serversAddFailed =>
      'Не удалось сохранить сервер. Попробуй ещё раз.';

  @override
  String get serversClipboardEmpty => 'В буфере обмена нет текста.';

  @override
  String get addKeyTitle => 'Добавить ключ';

  @override
  String get addKeyField => 'Ключ доступа';

  @override
  String get addKeyFieldHint => 'Вставь ключ или ссылку obsidian://';

  @override
  String get addKeyPaste => 'Вставить';

  @override
  String get addKeyNameField => 'Название, необязательно';

  @override
  String get addKeyNameHint => 'Например, Франкфурт';

  @override
  String addKeyRecognized(String hostPort) {
    return 'Распознано: $hostPort';
  }

  @override
  String get addKeySubmit => 'Добавить';

  @override
  String get qrTitle => 'Сканировать QR';

  @override
  String get qrHint => 'Наведи камеру на QR-код ключа';

  @override
  String get qrTorch => 'Фонарик';

  @override
  String get qrDeniedTitle => 'Нет доступа к камере';

  @override
  String get qrDeniedBody =>
      'Разреши доступ к камере в настройках системы, чтобы сканировать ключ. Или вставь ключ вручную.';

  @override
  String get qrError => 'Камера недоступна. Вставь ключ вручную.';

  @override
  String get splitTitle => 'Раздельный туннель';

  @override
  String get splitModeOff => 'Выкл';

  @override
  String get splitModeInclude => 'Только список';

  @override
  String get splitModeExclude => 'Кроме списка';

  @override
  String get splitOffNote =>
      'Весь трафик идет через VPN. Список ниже сохранится.';

  @override
  String get splitPresets => 'Готовые наборы';

  @override
  String splitPresetCount(int count) {
    return 'Адресов в наборе: $count';
  }

  @override
  String get splitEntries => 'Свои правила';

  @override
  String get splitEntriesHint => 'Домен, IP или подсеть в каждой строке';

  @override
  String splitAccepted(int count) {
    return 'Принято правил: $count';
  }

  @override
  String get splitIssues => 'Не распознано';

  @override
  String get splitEmptyWarning =>
      'Список пуст: через VPN сейчас ничего не идет.';

  @override
  String get splitNoteDomains => 'Домены повторно резолвятся каждые 10 минут.';

  @override
  String get splitNoteWildcards =>
      'Маски вроде *.ru не поддерживаются: укажи конкретный домен.';

  @override
  String get splitNoteIdn =>
      'Кириллические домены записывай в punycode, с префиксом xn--.';

  @override
  String get splitSave => 'Сохранить';

  @override
  String get splitSaved => 'Правила сохранены';

  @override
  String splitSavedSkipped(int count) {
    return 'Правила сохранены. Пропущено строк: $count';
  }

  @override
  String get splitLiveNote =>
      'Изменения сразу применятся к текущему подключению.';

  @override
  String get splitUnsavedTitle => 'Сохранить изменения?';

  @override
  String get splitUnsavedBody => 'Раздельный туннель изменён, но не сохранён.';

  @override
  String get splitDiscard => 'Не сохранять';

  @override
  String get splitKeepEditing => 'Остаться';

  @override
  String get splitMissing => 'Сервер не найден.';

  @override
  String get settingsSectionConnection => 'Подключение';

  @override
  String get settingsAutoConnect => 'Подключаться при запуске';

  @override
  String get settingsKillSwitch => 'Блокировать трафик без VPN';

  @override
  String get settingsKillSwitchIosCaption =>
      'Применяется при следующем подключении.';

  @override
  String get settingsKillSwitchAndroidCaption =>
      'Откроется системный раздел VPN. Включи «Постоянная VPN» и «Блокировать соединения без VPN» для Obsidian.';

  @override
  String get settingsSectionInterface => 'Интерфейс';

  @override
  String get settingsTheme => 'Тема';

  @override
  String get settingsThemeSystem => 'Системная';

  @override
  String get settingsThemeDark => 'Тёмная';

  @override
  String get settingsThemeLight => 'Светлая';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsLocaleSystem => 'Системный';

  @override
  String get settingsLocaleRu => 'Русский';

  @override
  String get settingsLocaleEn => 'English';

  @override
  String get settingsHaptics => 'Тактильный отклик';

  @override
  String get settingsSectionDesktop => 'Компьютер';

  @override
  String get settingsAutostart => 'Запускать вместе с системой';

  @override
  String get settingsMinimizeToTray => 'Сворачивать в трей при закрытии';

  @override
  String get settingsMinimizeToTrayCaption =>
      'Если выключено, закрытие окна завершает приложение.';

  @override
  String get settingsSectionDiagnostics => 'Диагностика';

  @override
  String get settingsConnectionLog => 'Журнал подключения';

  @override
  String get settingsDeviceId => 'ID устройства';

  @override
  String get settingsDeviceIdCopied => 'ID устройства скопирован';

  @override
  String get settingsSectionAbout => 'О приложении';

  @override
  String get settingsVersion => 'Версия';

  @override
  String get settingsProtocol => 'Протокол Obsidian v2, REALITY и UDP';

  @override
  String get logsClear => 'Очистить';

  @override
  String get trayOpen => 'Открыть';

  @override
  String get trayConnect => 'Подключить';

  @override
  String get trayDisconnect => 'Отключить';

  @override
  String get trayQuit => 'Выйти';
}
