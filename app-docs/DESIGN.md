# Obsidian VPN: design system

Design read: a precise network instrument cut from volcanic glass. Calm graphite surfaces,
one ember signal, the numbers that matter set in mono.

Dials: DESIGN_VARIANCE 4 (restrained, one strong hero), MOTION_INTENSITY 3 (motion only on
state change, nothing loops while idle or connected), VISUAL_DENSITY 5.

Metaphor: obsidian is cooled lava. Disconnected, the app is dark glass. Connected, ember
light shows through. Ember is the only brand color and it means "active / protected".

## Banned (these make it look AI-made)

- Purple, indigo or blue gradients. Gradient text. Neon glows. Glowing orbs.
- Glassmorphism and BackdropFilter blur (also costs battery).
- Three or four equal stat cards in a row. Cards inside cards.
- Emoji anywhere. Fake "military grade" security copy. Static marketing sheets.
- Default Material blue, default Roboto, heavy drop shadows, pill buttons everywhere.
- Centered stacks of everything. Every screen starting with a giant title.
- Em dash and en dash characters in any string.

## Color tokens (`lib/theme/tokens.dart`)

| Token | Dark | Light | Use |
|---|---|---|---|
| bg | #0B0C0E | #F4F3F0 | scaffold |
| surface | #131518 | #FFFFFF | rows, sheets |
| surfaceHi | #1A1D21 | #ECEAE6 | pressed, inputs, dial core |
| line | #26292E | #DEDBD5 | 1 px hairlines, dial idle segments |
| text | #EDEEF0 | #141517 | primary text |
| textDim | #8B9099 | #5E6269 | secondary |
| textFaint | #5A5F68 | #9A9DA3 | hints, units |
| ember | #FF6A2B | #E5531A | primary action, connected state |
| emberSoft | ember @ 14% | ember @ 12% | selected row bg, connected core tint |
| ok | #46C78A | #1F9D61 | ping good dot only |
| warn | #F5B83D | #B7791F | ping medium, warnings |
| danger | #E5484D | #CD2B31 | errors, destructive |

Elevation: none. Separation comes from `surface` on `bg` and 1 px `line` borders.
Dark is the default. Light follows the system setting.

## Type

Fonts are bundled: Manrope (UI) and JetBrains Mono (numbers, hosts, keys, timers, logs).
All numbers use `FontFeature.tabularFigures()`.

| Style | Font | Size/weight | Use |
|---|---|---|---|
| display | Mono | 34 / 600, tracking -0.5 | throughput values, session timer |
| title | Manrope | 22 / 700, tracking -0.4 | screen titles |
| heading | Manrope | 17 / 650 | section heads, sheet titles |
| body | Manrope | 15 / 500, height 1.4 | default |
| label | Manrope | 13 / 600 | buttons, row titles small |
| caption | Manrope | 12 / 500, textDim | hints |
| mono | Mono | 13 / 500 | hosts, keys, log lines |

## Space, radius, motion

- 4 pt grid: 4, 8, 12, 16, 20, 24, 32, 48. Screen gutter 20 (narrow), 24 (wide).
- Radius: 10 inputs and chips, 16 rows and groups, 24 sheets. Dial is a circle.
- Durations: 120 ms press, 220 ms state change, 320 ms sheet. Curve `Curves.easeOutCubic`.
- Press feedback: scale 0.97 on the dial and primary buttons. Ripples are subtle (alpha 0.08).
- Respect `MediaQuery.disableAnimations`: jump to end state.
- Allowed looping animation: only the connecting sweep on the dial, and only while connecting.

## Navigation and layout

- Width < 720: bottom bar with 4 items: Главная, Серверы, Доступ, Настройки. Custom bar,
  64 px, `surface`, top hairline, active item = ember icon + label, inactive textDim.
- Width >= 720: left rail 76 px with the same items, content column max 560 px centered.
- Desktop window: default 420 x 760, min 380 x 640, resizable. Windows and Linux: custom
  40 px title area with drag region, minimize and close (window_manager). macOS: keep traffic
  lights, transparent title bar.
- Sheets: modal bottom sheet on phones, centered dialog max 480 px wide on desktop. One helper:
  `showAdaptiveSheet()`.
- Icons: Material rounded set (`Icons.*_rounded`), 22 px, stroke look. No mixed icon sets.

## Platform feel

- iOS and macOS: Cupertino page transitions, bouncing scroll, `Switch.adaptive`,
  haptics (light on tap, medium on connected). Android: predictive back, Material 3 switches.
- Desktop: hover states (surfaceHi), pointer cursor on clickables, keyboard: Space/Enter
  toggles connection on Home, Ctrl+V on Servers opens add key with clipboard prefilled.
- Text is selectable where it is data (hosts, keys, logs).

## Home screen (the hero)

Top: small wordmark "obsidian" in Manrope 600 lowercase, textDim, left aligned. Right: a
status word in mono caption: `ОТКЛЮЧЕНО`, `ПОДКЛЮЧЕНИЕ 2/4`, `ЗАЩИЩЕНО`, `ПЕРЕПОДКЛЮЧЕНИЕ`, `ОШИБКА`.

The dial, 220 px, slightly above vertical center:
- Outer ring of 4 arc segments (84 degrees each, 6 degree gaps, 6 px stroke, round caps).
  Each segment is one real connection stage. Idle: `line`. Connecting: segments fill ember
  one by one as stages arrive (220 ms each); a short 30 degree ember sweep rotates over the
  ring while connecting. Connected: all 4 ember, no motion. Error: the failed stage segment
  turns danger.
- Core circle 168 px, `surfaceHi`. Connected: static radial ember tint (emberSoft) from the
  center. Power glyph 36 px, textDim idle, ember connected.
- Under the dial, one line: action word ("Подключить", "Отмена", "Отключить", "Повторить")
  in label style, and in connected state the session timer in display mono.
- Error text: one or two lines, danger, under the dial, plus "Журнал" text button.

Below: server row (full width, surface, radius 16): country code in a 32 px mono box,
name, host in mono caption, ping value with a 6 px dot (ok < 80 ms, warn < 160, danger above),
chevron. Tap opens server picker sheet.

Then, only when connected: one traffic row with two columns divided by a hairline:
"Загрузка" and "Отдача", value in display mono (e.g. `12.4`) + unit caption (`Мбит/с`),
and total bytes in caption below. Not cards.

Then a split tunnel row: "Раздельный туннель" + summary ("Выключен", "Исключений: 12",
"Только список: 4").

## Other screens (keep the same vocabulary)

- Lists are grouped rows on `surface` with hairline separators, radius 16 per group.
- Section labels: caption, textDim, sentence case, 8 px above group.
- Primary button: ember fill, text #0B0C0E, height 48, radius 12, full width in sheets.
  Secondary: surfaceHi fill. Destructive: danger text on surfaceHi.
- Inputs: surfaceHi fill, no border until focus (1 px ember), radius 10, mono for keys/hosts.
- Empty state: one sentence + one primary action, left aligned, no illustration.
- Toasts: bottom, surfaceHi, 2.2 s, one line.
- Deploy console: mono 12, bg surface, autoscroll, max 400 lines in memory.
- Issued key: QR on white square (radius 16, 16 px quiet zone) for scanner reliability in both themes.

## Copy

Russian first, English second (ARB). Short, concrete, no hype. Errors say what happened and
what to do: "Сервер не отвечает на порту 443. Проверь, что VPS запущен." Never print keys or
tokens except on screens whose purpose is showing them.
