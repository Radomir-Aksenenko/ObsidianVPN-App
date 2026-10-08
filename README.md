# Obsidian VPN

Obsidian VPN это одно приложение на Flutter для Windows, macOS, Linux, Android и iOS. Оно подключается к VPN-серверу на Go и умеет установить этот сервер на ваш VPS по SSH. Ядро VPN находится в публичном репозитории ObsidianVPN и подключено сюда как submodule в каталоге `core/`.

## Структура репозитория

- `app/` - приложение на Flutter: интерфейс, логика и нативные части для каждой платформы (`android/`, `ios/`, `macos/`, `linux/`, `windows/`).
- `core/` - submodule с Go-ядром: `cmd/client`, `cmd/server`, `pkg/mobile`.
- `server/keyserver.py` - скрипт keyserver, который приложение ставит на VPS вместе с ядром.
- `scripts/` - сборка Go-бинарников в `app/assets/bin/` (`build-core-assets.ps1` и `.sh`), загрузка `wintun.dll` (`fetch-wintun.ps1`), проставление версии (`set-version.mjs`).
- `app-docs/` - архитектура, дизайн и описания прежних клиентов.
- `.github/workflows/` - сборка и релизы.
- `VERSION` - номер версии. Из него берётся версия релиза.

## Клонирование

```sh
git clone --recurse-submodules <адрес репозитория>
# если core/ пустой:
git submodule update --init --recursive
```

## Сборка и релизы в CI

Приложения собираются только в GitHub Actions. Workflow `app.yml` запускает сборку под Android, iOS, macOS, Linux и Windows. Workflow `release.yml` публикует результат.

- Push в `main` заменяет файлы предрелиза `nightly` свежими сборками.
- Тег `vX.Y.Z`, совпадающий с `VERSION`, создаёт релиз с заметками. Если тег не совпадает с `VERSION`, публикация останавливается с ошибкой.

## Выпуск версии

1. Изменить `VERSION`, например на `2.0.1`.
2. Выполнить `node scripts/set-version.mjs`. Скрипт запишет версию в `app/pubspec.yaml` как `2.0.1+1`. Номер сборки CI заменяет сам.
3. Закоммитить изменения.
4. Создать и отправить тег: `git tag v2.0.1`, затем `git push origin main v2.0.1`.

## Установка

- **Windows**: запустите установщик `setup.exe`.
- **Android**: для большинства телефонов подходит APK с пометкой `arm64-v8a`. В релизе есть и другие варианты APK для старых и x86 устройств.
- **iOS**: IPA в релизе не подписан. Установите его через AltStore или Sideloadly с вашим Apple ID.
- **macOS**: при первом запуске откройте приложение через правый клик и пункт «Открыть». Затем подтвердите запуск.
- **Linux**: распакуйте архив `tar.gz`. Туннелю нужны права root, поэтому приложение запрашивает их через `pkexec`.

## Локальная разработка

Локально проверяются анализ кода и тесты. Сборки выполняются только в CI.

```sh
cd app
flutter analyze
flutter test
```

## Обновление ядра

```sh
git -C core fetch origin
git -C core checkout origin/main
git add core
git commit -m "build: update core"
```

Указатель submodule фиксирует конкретный коммит, поэтому сборка воспроизводима. Версия ядра меняется только этим коммитом.
