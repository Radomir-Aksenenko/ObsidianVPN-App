# Obsidian VPN

Клиенты Obsidian VPN для Windows и iPhone. VPN-ядро на Go находится в публичном репозитории ObsidianVPN и подключено сюда как submodule в каталоге `core/`.

## Что внутри

- `desktop/` - приложение для Windows на Tauri 2 (интерфейс в `desktop/src`, логика на Rust в `desktop/src-tauri`).
- `ios/` - клиент для iPhone на SwiftUI с Packet Tunnel Provider. Go Mobile XCFramework собирается из `core/pkg/mobile`.
- `core/` - submodule с ядром: `cmd/client`, `cmd/server`, `pkg/mobile`.
- `scripts/` - локальная сборка десктопа, загрузка wintun, проставление версии.
- `.github/workflows/` - сборка и релизы.
- `VERSION` - единый источник версии для всех клиентов.

## Локальная сборка

Клонирование с submodule:

```sh
git clone --recurse-submodules <адрес репозитория>
# если core/ пустой:
git submodule update --init --recursive
```

Windows (нужны Go, Node.js 22+ и Rust, как для любого проекта на Tauri):

```bat
scripts\build-desktop.bat
```

Скрипт собирает `obsidian-client.exe` и `obsidian-server-linux` из `core/`, скачивает `wintun.dll` (версия 0.14.1, SHA256 проверяется) и запускает `npx tauri build`. Установщик появится в `desktop\src-tauri\target\release\bundle\nsis\`.

iPhone (нужен macOS с Xcode, XcodeGen и gomobile):

```sh
cd core
gomobile bind -target=ios,iossimulator -o ../ios/Frameworks/Obsidian.xcframework ./pkg/mobile
cd ../ios
xcodegen generate
open ObsidianVPN.xcodeproj
```

Подпись, Team и Network Extension настраиваются в `ios/README.md`.

## CI

- `ios.yml` собирает неподписанный `.ipa` (артефакт `ios-ipa`).
- `desktop.yml` собирает установщик Windows (артефакт `windows-installer`).
- Оба запускаются на pull request и вручную (`workflow_dispatch`). Для push в main их вызывает `release.yml`.
- `release.yml`: push в main обновляет предрелиз `nightly` (старые файлы заменяются новыми). Tag `v*` создаёт релиз с заметками.

## Выпуск версии

1. Изменить `VERSION`, например на `1.2.0`.
2. Выполнить `node scripts/set-version.mjs`, чтобы обновить `desktop/`, `ios/project.yml` и `Cargo.lock`.
3. Закоммитить изменения.
4. Создать и отправить тег: `git tag v1.2.0`, затем `git push origin main v1.2.0`.

Тег должен совпадать с `VERSION`, иначе публикация остановится с ошибкой. Номер сборки iOS (`CURRENT_PROJECT_VERSION`) CI выставляет сам по номеру запуска.

## Обновление ядра

```sh
git -C core fetch origin
git -C core checkout origin/main
git add core
git commit -m "build: update core"
```

Указатель submodule фиксирует конкретный коммит, поэтому сборка воспроизводима. Версия ядра меняется только этим коммитом.
