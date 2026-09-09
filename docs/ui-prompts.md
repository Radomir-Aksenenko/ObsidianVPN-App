# Промты для генерации макетов ObsidianVPN

Как пользоваться: копируете **блок стиля** и следом **промт нужного экрана** в одно сообщение. Каждый промт самодостаточный, порядок и история чата не важны.

Почему подписи на английском: модели генерации изображений плохо рисуют кириллицу, буквы поедут. Русские строки уже лежат в коде, я подставлю их при реализации. От картинки нужна композиция, иерархия и настроение.

Формат: **вертикальный 2:3** для всех экранов. Окно приложения на компьютере такое же узкое, как на телефоне, поэтому отдельных горизонтальных макетов не нужно.

---

## Блок стиля (вставлять перед каждым промтом)

```
Design an application UI mockup. Flat 2D screenshot of the interface itself, filling the entire frame edge to edge, portrait orientation. No phone or laptop mockup, no perspective, no hands, no room, no browser chrome.

Product: Obsidian VPN, a privacy tool that also lets you deploy your own VPN server.
Reference: the desktop AmneziaVPN client. A narrow portrait window, mostly empty black, one huge ring in the middle carrying the connection state, a card pinned to the bottom naming the current server, and a row of icon-only navigation under it.
Tone: calm and confident. Almost nothing on screen, and what is there is large.

Palette, use exactly:
- background: near-black #0C0D12
- panel surfaces: #181A23, raised #1F2230
- hairline borders: white at 8-15% opacity
- primary text: #F3F4F8, secondary #9096A8, muted #5D6274
- the single accent, blue-violet periwinkle: #7A85FF, with #A3AAFF for glow
- warning amber #E0A33F, error red #F25563
The accent is expensive: it appears on the connection ring, on one primary button, and on the selected navigation icon. Nowhere else. Everything else is cool grey on black.

Texture: a very fine film grain over the whole interface at low opacity. Felt, not noticed. No template gradients, no glassmorphism blur, no rainbow lighting.

Typography: one sans family throughout (Manrope style), hierarchy carried by size and weight alone. The server name is large and bold, around 34px. Technical values (IP addresses, timers, keys) in a monospace (JetBrains Mono style).

Shapes: rounded panels (about 22-28px), pill buttons, 44px+ touch targets, 4pt spacing rhythm. Icons are thin-stroke line icons (Lucide style), 1.5px stroke, never filled, never emoji.

Avoid: three identical cards in a row, sidebars, dashboards, dense tables, drop shadows on text, fake charts, lorem ipsum, watermarks, gibberish letterforms.

All labels in English.
```

---

## 1. Главный экран, отключено

```
Screen: Connect, disconnected state. Portrait window, roughly 440 by 820.

Top: a slim window title bar, 40px, empty except for minimize / maximize / close glyphs at the right in muted grey.

Middle, taking most of the height and vertically centered:
- One large open circle, about 268px across, drawn as a 2px hairline ring in muted grey (#5D6274). The inside of the circle is empty: the black background shows straight through. Nothing glows.
- Centered inside the ring, one word in medium grey, around 20px semibold: "Connect"

Lower area:
- A small pill-shaped row, centered, containing a 26px rounded square with a split-path line icon, the muted text "Split tunneling off", and a small chevron-down.
- Under it, pinned to the bottom, a card with rounded top corners only, slightly lighter than the background. It has a short grab handle bar centered at its top. Inside: the server name "Frankfurt" very large and bold (about 34px) with a chevron-down beside it, and under it one muted line in monospace: "Obsidian v2  |  95.85.231.206"
- Below the card, a navigation row of four icon-only buttons evenly spaced: house (currently muted), people, gear, plus. No labels.

Mood: switched off and waiting. Most of the screen is black, and the ring is the only thing asking to be touched.
```

---

## 2. Главный экран, подключено

```
Screen: Connect, tunnel up. Portrait window, roughly 440 by 820.

Same structure as the disconnected state, but the ring is alive.

- The large circle is now a clean 2px ring in blue-violet #7A85FF, closed all the way round, with a soft wide halo of the same colour bleeding outward and fading to black well before the edges of the window. The inside of the circle stays pure black.
- Centered inside the ring: "Connected" in #7A85FF, around 20px semibold.
- Directly under the ring, small and muted, a monospace timer: "00:42:17"
- The split-tunneling pill row sits lower down, unchanged and muted.
- The bottom card shows "Frankfurt" very large and bold, with a small padlock icon beside it instead of a chevron, and the muted monospace line "Obsidian v2  |  95.85.231.206"
- Bottom navigation: four icons, the house icon now in accent blue-violet, the rest muted.

Mood: one calm ring of light in a dark room. The halo is the only bright thing on screen.
```

---

## 3. Главный экран, идёт подключение

```
Screen: Connect, negotiating the tunnel. Portrait window, roughly 440 by 820.

Same structure as the other connect states.

- The large circle shows a hairline grey ring, and over it a single bright arc of #A3AAFF covering about three eighths of the circumference, frozen mid-rotation: bright and rounded at its leading edge, fading to fully transparent at its tail. A faint halo sits behind the arc only.
- Centered inside the ring: "Connecting" in #A3AAFF.
- No timer yet under the ring.
- The split-tunneling pill row and the bottom card are unchanged, the card showing "Frankfurt" with a padlock.
- Bottom navigation: four icons, house active.

Mood: motion implied by one arc, everything else perfectly still.
```

---

## 4. Экран серверов

```
Screen: Servers list. Portrait window, roughly 440 by 820.

Top: slim window title bar with window controls at the right.

Content, 16px side padding:
- A heading "Servers" (about 26px bold) with one muted line under it: "Connect with a key, or deploy your own"
- A row of two equal-width pill buttons side by side: a solid accent blue-violet one with a plus icon reading "Key", and an outlined dark one with a download icon reading "Own server"
- A vertical stack of server rows, 8px apart. Each row is a rounded rectangle panel containing: a 38px rounded square badge with a server line icon, then the name in semibold with the address under it in muted monospace, then a copy icon and a trash icon at the right.
  First row is selected: its border is accent blue-violet at low opacity, its badge is accent-tinted, and a small accent dot sits after the name. Name "Frankfurt", address "95.85.231.206:8443".
  Second row is plain grey. Name "Amsterdam", address "203.0.113.10:9000".
- Empty black space below the rows. Do not invent extra rows to fill it.
- Bottom navigation: four icons, the plus icon active in accent.

Mood: a short list you own, not a catalogue.
```

---

## 5. Добавление ключа

```
Screen: Add key, a sheet rising from the bottom over a dimmed Servers screen. Portrait window.

Background: the Servers list, dimmed to about 40%.

Foreground: a rounded panel occupying the lower two thirds of the window, raised surface, hairline border.
Inside, top to bottom:
- Heading "Add a key" (about 20px bold)
- One muted line: "Paste the OBSDN-XXXX-XXXX string your admin gave you"
- A large multi-line text field, 4 lines tall, sunken darker background, containing a realistic wrapped key in small monospace: "OBSDN-PDNK-KT25-BOBT-ADH4-F735-ZVNE-5VIP-E3YE-BORD-RCWW-GEMP". Its border is accent blue-violet, showing it validated.
- Under the field, a line with a small circled check icon in accent: "95.85.231.206:8443 · expires 2027-01-01 · up to 3 devices"
- At the bottom, two equal-width buttons side by side: an outlined "Cancel" and a solid accent "Add".

Mood: the app understood the key before anything was pressed.
```

---

## 6. Установка сервера, шаг 1

```
Screen: Deploy server wizard, step 1 of 3. Portrait window, full height, no bottom navigation.

Top bar: on the left, "Deploy server" in semibold with a muted line under it reading "Step 1 of 3: Access". On the right, three small progress dots where the first is an elongated accent-blue pill and the other two are short grey dashes, then a close X icon.

Content, 16px padding, scrollable:
- Heading "Your own server in a couple of minutes" (about 26px bold)
- Two muted lines: "Needs a clean Ubuntu or Debian machine with root SSH access. The app installs Docker, deploys the server, configures NAT, and hands you a ready key."
- One rounded panel holding a single-column form. Each field is a small label above a sunken rounded input:
  "Server address" with value 95.85.231.206
  "SSH port" with value 22
  "User" with value root
  "Root password" filled with password dots
  "Profile name" with placeholder "optional"
  "VPN port" with value 8443
- A small muted line with a padlock icon: "The password is used for this install only and is never written to disk."
- Two buttons at the bottom: outlined "Cancel" and solid accent "Install" with a play icon.

Mood: a serious operation presented calmly.
```

---

## 7. Установка сервера, шаг 2, живой лог

```
Screen: Deploy server wizard, step 2 of 3, running. Portrait window, full height, no bottom navigation.

Top bar: "Deploy server" with the muted line "Step 2 of 3: Install". Progress dots show the second one as the elongated accent pill. The close X is dimmed.

Content:
- A row with a small circular spinner and the heading "Installing on 95.85.231.206"
- One muted line: "Usually takes 2 to 4 minutes. Do not close the window."
- A terminal panel filling the rest of the height: sunken near-black rounded rectangle, hairline border, dense small monospace lines. Colour-code them: lines starting with "$" in accent blue-violet, section headers like "--- Docker ---" in bright white, lines prefixed "[stderr]" in amber, everything else muted grey. Realistic content: apt-get output, "docker run -d --name obsidian-vpn", "Public key: 9f2c...", "NAT via eth0, opened ports 8443". Scrolled to the bottom.

Mood: honest machinery, nothing hidden.
```

---

## 8. Установка сервера, шаг 3, готово

```
Screen: Deploy server wizard, step 3 of 3, finished. Portrait window, full height.

Top bar: "Deploy server" with the muted line "Step 3 of 3: Done". The third progress dot is the elongated accent pill.

Content:
- A row with a circled check icon in accent blue-violet and the heading "Server is ready"
- One muted line: "The profile is already in your list. Share the key below with your other devices."
- A rounded panel holding three labelled values stacked vertically, split by hairline dividers. Each has a small uppercase label, the value, and a copy icon at the right:
  "CONNECTION KEY" with a long wrapped monospace OBSDN string
  "KEY SERVER" with "http://95.85.231.206:8444"
  "ADMIN TOKEN" with a long hex token in monospace
- A warning line with a small triangle icon in amber: "Save the admin token, it is shown only once."
- A full-width solid accent button at the bottom with a check icon: "Done"

Mood: a receipt worth keeping.
```

---

## 9. Доступы, список своих серверов

```
Screen: Access, where you hand out keys for servers you deployed yourself. Portrait window.

Content, 16px padding:
- Heading "Access" with one muted line: "Issue keys for your own servers"
- A slim inline row of three stats separated by thin vertical dividers, NOT boxed cards: "7 keys", "12 devices", "2 expiring". Numbers in bold, labels small and muted.
- One rounded panel per owned server. Inside each: a 38px accent-tinted rounded badge with a server-with-gear icon, the server name in semibold, the address under it in muted monospace, and below them a full-width solid accent pill button with a person-plus icon reading "Issue key", with a small outlined key icon button beside it.
- Under the first server panel, a compact list of already issued keys as rows split by hairline dividers: a small circular avatar with two initials, the label in semibold ("Anna laptop"), the key tail in muted monospace ("key ...GEMP"), a device count "2 / 3" in monospace, and a small status pill at the right: accent "active" for most, amber "expiring" for one, dim red "revoked" for one.
- Bottom navigation: four icons, the people icon active in accent.

Mood: a ledger, dense but breathable. No charts.
```

---

## 10. Выдача ключа

```
Screen: Issue key, a sheet rising from the bottom over a dimmed Access screen. Portrait window.

Foreground panel, lower two thirds:
- Heading "Issue a key" with a muted line: "The key carries the server address and settings, no server call needed"
- Field "For whom" with a sunken input containing "Anna laptop"
- Label "Valid for" with a row of four pill chips: "30 days", "90 days", "1 year" (this one selected, accent border and accent-tinted fill), "Forever"
- A row with the label "Devices per key" on the left and a pill-shaped stepper on the right: minus, the number 3, plus
- Two equal buttons at the bottom: outlined "Cancel" and solid accent "Create"

Mood: a small precise instrument.
```

---

## 11. Выданный ключ с QR

```
Screen: Issue key, result state, a sheet over a dimmed Access screen. Portrait window.

Foreground panel:
- Heading "Issue a key" with the same muted subtitle
- A white rounded square centered near the top containing a crisp black QR code, about 148px
- Under it, a sunken rounded panel with a hairline border containing the full key wrapped across three lines in small monospace: "OBSDN-PDNK-KT25-BOBT-ADH4-F735-ZVNE-5VIP-E3YE-BORD-RCWW-GEMP-X346-XZWO"
- Two equal buttons at the bottom: outlined "One more" and solid accent "Copy" with a copy icon

Mood: hand it over and be done.
```

---

## 12. Настройки

```
Screen: Settings. Portrait window.

Content, 16px padding:
- Heading "Settings"
- Three groups. Each has a tiny uppercase muted label above it, then one rounded panel whose rows are split by hairline dividers indented past the icon. Each row has a thin line icon at the left, a title, a muted second line, and a control at the right.
  "STARTUP": row "Launch at sign-in" / "Starts together with Windows" with a toggle, off. Row "Minimize to tray" / "Closing the window keeps the app in the notification area" with a toggle, on and accent blue-violet.
  "SECURITY": row "Block traffic on drop" / "If the tunnel dies, plain internet does not come back on its own" with a toggle, off.
  "ABOUT THIS DEVICE": row "Device ID" with a monospace UUID and a copy icon. Row "Data folder" with a monospace Windows path and a copy icon. Row "Version" with "1.0.0 · Obsidian v2" in monospace and no control.
- Bottom navigation: four icons, the gear active in accent.

Mood: readable in one pass.
```

---

## Что мне прислать обратно

Достаточно картинок с номерами экранов. Если по какому-то экрану сгенерируете несколько вариантов, скажите, какой берём, либо пришлите все и я предложу.

Полезно, но не обязательно: если в макете появится элемент, которого нет в списке выше, отметьте его словами, чтобы я не гадал по пикселям.

Экраны 1, 2, 3, 4, 9 и 12 уже собраны в коде по этому описанию, так что макеты по ним можно сравнивать напрямую с тем, что запускается. Экраны 10 и 11 собраны частично, экраны 5 и 6-8 существуют, но их вид точно поменяется под макет.
