// ObsidianVPN Desktop Client v2.0
// High-precision industrial dark UI with reactive state & zero-flicker rendering

const hasTauri = () => typeof window !== "undefined" && Boolean(window.__TAURI__);
const invoke = (cmd, args) => {
  if (hasTauri()) return window.__TAURI__.core.invoke(cmd, args);
  console.warn("[Tauri Mock] invoke:", cmd, args);
  return Promise.resolve({});
};
const listen = (ev, fn) => {
  if (hasTauri()) return window.__TAURI__.event.listen(ev, fn);
  return Promise.resolve(() => {});
};
const win = () => {
  if (hasTauri()) return window.__TAURI__.window.getCurrentWindow();
  return {
    minimize: () => console.log("win.minimize"),
    close: () => console.log("win.close"),
  };
};

// Официальные эталонные векторные иконки (Lucide 24x24, 1.8px stroke)
const I = {
  hex: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><polygon points="12 2 21.5 7.5 21.5 16.5 12 22 2.5 16.5 2.5 7.5 12 2"/></svg>`,
  power: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18.36 6.64a9 9 0 1 1-12.73 0"/><line x1="12" y1="2" x2="12" y2="12"/></svg>`,
  shield: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>`,
  home: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>`,
  servers: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="8" x="2" y="2" rx="2" ry="2"/><rect width="20" height="8" x="2" y="14" rx="2" ry="2"/><line x1="6" x2="6.01" y1="6" y2="6"/><line x1="6" x2="6.01" y1="18" y2="18"/></svg>`,
  key: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m21 2-2 2m-1.5 1.5L14 9l-4-4-6 6 4 4 1-1v-2h2v-2h2v-2h2l3.5-3.5"/></svg>`,
  gear: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></svg>`,
  plus: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>`,
  trash: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/></svg>`,
  refresh: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.85.83 6.72 2.24L21 8"/><path d="M21 3v5h-5"/></svg>`,
  chev: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>`,
  back: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>`,
  copy: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>`,
  paste: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect width="8" height="4" x="8" y="2" rx="1" ry="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/></svg>`,
  check: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`,
  terminal: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>`,
  sliders: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><line x1="4" x2="4" y1="21" y2="14"/><line x1="4" x2="4" y1="10" y2="3"/><line x1="12" x2="12" y1="21" y2="12"/><line x1="12" x2="12" y1="8" y2="3"/><line x1="20" x2="20" y1="21" y2="16"/><line x1="20" x2="20" y1="12" y2="3"/><line x1="1" x2="7" y1="14" y2="14"/><line x1="9" x2="15" y1="8" y2="8"/><line x1="17" x2="23" y1="16" y2="16"/></svg>`,
  lock: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`,
  eye: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></svg>`,
  eyeOff: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9.88 9.88a3 3 0 1 0 4.24 4.24"/><path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68"/><path d="M6.61 6.61A13.526 13.526 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61"/><line x1="2" y1="2" x2="22" y2="22"/></svg>`,
  alert: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>`,
  min: `<svg width="10" height="10" viewBox="0 0 10 10"><line x1="1" y1="5" x2="9" y2="5" stroke="currentColor" stroke-width="1.2"/></svg>`,
  close: `<svg width="10" height="10" viewBox="0 0 10 10"><line x1="1.5" y1="1.5" x2="8.5" y2="8.5" stroke="currentColor" stroke-width="1.2"/><line x1="8.5" y1="1.5" x2="1.5" y2="8.5" stroke="currentColor" stroke-width="1.2"/></svg>`,
};

// Чтение начального маршрута из параметров URL (для отладки и скриншотов)
const initialParams = typeof window !== "undefined" && window.location ? new URLSearchParams(window.location.search) : null;
const initialRoute = initialParams?.get("route") || "home";
const initialModal = initialParams?.get("modal") || null;
const initialServerId = initialParams?.get("server") || null;
const initialVpnStatus = initialParams?.get("vpn_status") || "disconnected";
const initialVpnProgress = Number(initialParams?.get("vpn_progress") || 0);
const initialVpnStage = initialParams?.get("vpn_stage") || null;
const initialVpnDetail = initialParams?.get("vpn_detail") || null;
const initialManageLoading = initialParams?.get("manage_loading") || null;
const initialManageProgress = initialParams?.get("manage_progress")
  ? { pct: Number(initialParams.get("manage_progress")), stage: initialParams.get("manage_stage") || "Выполнение операции..." }
  : (initialManageLoading ? { pct: 62, stage: "Установка контроллера ключей..." } : null);
const initialDeployStep = Number(initialParams?.get("deploy_step") || 1);
const initialDeployProgress = Number(initialParams?.get("deploy_progress") || 0);

// Глобальное состояние приложения
const state = {
  route: initialRoute, // "home" | "servers" | "access" | "settings" | "deploy" | "issue" | "issued" | "server-manage"
  modal: initialModal, // "add-key" | "split" | "confirm-delete" | "confirm-reset"
  deleteCandidate: null,
  manageLoading: initialManageLoading, // "sni" | "update" | "check" | "reset" | "save-cred"
  manageProgress: initialManageProgress, // { pct: number, stage: string }
  data: {
    profiles: [],
    issued: [],
    settings: { autostart: false, minimize_to_tray: true, kill_switch: false, last_profile_id: "" },
    device_id: "----",
    version: "0.1.0",
    vpn: {
      status: initialVpnStatus,
      error: null,
      detail: initialVpnDetail,
      connected_at: null,
      profile_id: null,
      progress: initialVpnProgress,
      stage: initialVpnStage,
    },
  },
  pings: {},
  deploy: {
    kind: "deploy",
    step: initialDeployStep,
    log: initialParams?.get("deploy_log") || "Подключение к 203.0.113.50:22...\nУстановка Docker компонентов...\nКонфигурация REALITY на порту 443 с маскировкой www.microsoft.com...\nКлючи шифрования сгенерированы успешно\n",
    progress: initialDeployProgress,
    result: null,
    auth: "password",
    keyPath: "",
    keyLabel: "",
    host: "",
    user: "root",
    port: "22",
    password: "",
    mask: "www.microsoft.com",
  },
  issue: { name: "Гость", days: 30, devices: 3, made: null, qr: "" },
  keyDraft: "",
  keyHint: null,
  splitDraft: "",
  managingServerId: initialServerId,
  manageSniDraft: "",
  manageCreds: null,
};

function esc(s) {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function selectedProfile() {
  const id = state.data.settings.last_profile_id;
  return state.data.profiles.find((p) => p.id === id) || state.data.profiles[0] || null;
}

function ownServer(id) {
  if (id) return state.data.profiles.find((p) => p.id === id && p.source === "ssh") || null;
  const sel = selectedProfile();
  if (sel?.source === "ssh") return sel;
  return state.data.profiles.find((p) => p.source === "ssh") || null;
}

function elapsed(since) {
  if (!since) return "00:00:00";
  const s = Math.max(0, Math.floor(Date.now() / 1000 - since));
  const hh = String(Math.floor(s / 3600)).padStart(2, "0");
  const mm = String(Math.floor((s % 3600) / 60)).padStart(2, "0");
  const ss = String(s % 60).padStart(2, "0");
  return `${hh}:${mm}:${ss}`;
}

function pingOf(p) {
  if (!p) return null;
  return state.pings[p.id];
}

function pingDotClass(ms) {
  if (ms == null) return "";
  if (ms < 80) return "fast";
  if (ms < 160) return "medium";
  return "slow";
}

function splitSummary(p) {
  if (!p) return "Выключено";
  const sites = p.config?.split_sites || p.config?.route_ips || [];
  if (!sites.length) return "Выключено";
  return `Исключений: ${sites.length}`;
}

function countryCodeOf(p) {
  if (!p) return "VPN";
  if (p.code && p.code.length <= 4) return p.code.toUpperCase();
  if (p.source === "ssh") return "VPS";
  const n = (p.name || "").toLowerCase();
  if (n.includes("netherland") || n.includes("amsterdam")) return "NL";
  if (n.includes("german") || n.includes("frankfurt")) return "DE";
  if (n.includes("finland") || n.includes("helsinki")) return "FI";
  if (n.includes("usa") || n.includes("united states") || n.includes("america")) return "US";
  if (n.includes("russia") || n.includes("moscow")) return "RU";
  return (p.name || "VPN").slice(0, 3).toUpperCase();
}

function showToast(text, type = "info") {
  const root = document.getElementById("toast-root");
  if (!root) return;
  const el = document.createElement("div");
  el.className = `toast-msg ${type}`;
  el.textContent = text;
  root.appendChild(el);
  setTimeout(() => {
    el.style.opacity = "0";
    el.style.transform = "translateY(8px)";
    el.style.transition = "all 0.18s ease";
    setTimeout(() => el.remove(), 200);
  }, 2200);
}

// Верхний Titlebar
function renderTitlebar(opts = {}) {
  const back = opts.back
    ? `<button class="titlebar-back-btn" data-act="back" title="Назад">${I.back}</button><div class="titlebar-title">${opts.title}</div>`
    : `<div class="brand-badge">${I.hex}<span>ObsidianVPN</span></div>`;
  return `
    <div class="app-titlebar" data-tauri-drag-region>
      ${back}
      <div class="titlebar-spacer" data-tauri-drag-region></div>
      <div class="titlebar-actions" data-tauri-drag-region="false">
        <button class="win-control-btn" data-act="min" title="Свернуть">${I.min}</button>
        <button class="win-control-btn close" data-act="close" title="Закрыть">${I.close}</button>
      </div>
    </div>`;
}

// Нижняя навигация
function renderBottomNav(active) {
  const item = (id, icon, label) => `
    <button class="nav-tab-btn ${active === id ? "active" : ""}" data-nav="${id}" title="${label}">
      ${icon}
    </button>`;
  return `
    <nav class="desktop-nav-bar">
      ${item("home", I.home, "Главная")}
      ${item("servers", I.servers, "Серверы")}
      ${item("access", I.key, "Доступ")}
      ${item("settings", I.gear, "Настройки")}
    </nav>`;
}

// Главный экран (Home)
function renderHomeView() {
  const vpn = state.data.vpn;
  const p = selectedProfile();
  const st = vpn.status;

  let dialClass = "disconnected";
  let actionText = "Подключить";
  let statusText = "ОТКЛЮЧЕНО";
  let statusClass = "";
  let timerHtml = "";
  let detailHtml = "";

  if (st === "connecting") {
    dialClass = "connecting";
    actionText = "Отмена";
    statusText = "ПОДКЛЮЧЕНИЕ...";
    statusClass = "live";
    const stage = vpn.stage || "Подготовка соединения...";
    const pct = Math.max(0, Math.min(100, Math.round(vpn.progress || 0)));
    const taskbarHtml = `
      <div class="process-taskbar connecting-taskbar">
        <div class="process-taskbar-meta">
          <span class="process-taskbar-stage">${esc(stage)}</span>
          <span class="process-taskbar-pct">${pct}%</span>
        </div>
        <div class="process-taskbar-track">
          <div class="process-taskbar-fill" style="width: ${Math.max(4, pct)}%;"></div>
        </div>
      </div>`;
    detailHtml = `${taskbarHtml}<div class="connection-sub-note">${esc(vpn.detail || "Запуск сетевого интерфейса...")}</div>`;
  } else if (st === "connected") {
    dialClass = "connected";
    actionText = "Отключить";
    statusText = "ПОДКЛЮЧЕНО";
    statusClass = "live";
    timerHtml = `<div class="session-clock">${elapsed(vpn.connected_at)}</div>`;
    const host = p?.config?.server_host || "";
    const port = p?.config?.server_port || "443";
    detailHtml = `<div class="connection-sub-note">${esc(host)}:${esc(port)} · REALITY</div>`;
  } else if (st === "error") {
    dialClass = "error";
    actionText = "Повторить";
    statusText = "ОШИБКА";
    statusClass = "err";
    detailHtml = `<div class="connection-sub-note error-msg">${esc(vpn.error || "Не удалось установить соединение")}</div>`;
  }

  const dialButton = `
    <button class="connection-dial ${dialClass}" data-act="toggle-vpn" title="${actionText}">
      <svg class="dial-svg" viewBox="0 0 172 172">
        <circle class="dial-track" cx="86" cy="86" r="76"/>
        ${st === "connecting"
          ? `<circle class="dial-live-arc dial-spinner" cx="86" cy="86" r="76" stroke-dasharray="110 370"/>`
          : st === "connected"
          ? `<circle class="dial-live-arc" cx="86" cy="86" r="76"/>`
          : ""}
      </svg>
      <div class="dial-inner-plate">
        <div class="dial-glyph">${I.power}</div>
        <div class="dial-btn-text">${actionText}</div>
      </div>
    </button>`;

  let serverCardHtml = "";
  if (p) {
    const ms = pingOf(p);
    const pingText = ms != null ? `${ms} ms` : "…";
    const dotClass = pingDotClass(ms);
    const code = countryCodeOf(p);
    serverCardHtml = `
      <div class="server-dock-card">
        <button class="server-dock-main" data-nav="servers" title="Выбрать другой сервер">
          <div class="country-iso-tag">${esc(code)}</div>
          <div class="server-title-group">
            <div class="server-title-name">${esc(p.name)}</div>
            <div class="server-title-stats">
              <span>${esc(p.config?.server_host || "Сервер")}</span>
              <span class="stat-separator"></span>
              <span class="latency-meter">
                <span class="latency-dot ${dotClass}"></span>
                ${pingText}
              </span>
            </div>
          </div>
          <div class="card-chev-icon">${I.chev}</div>
        </button>
        <div class="card-inner-split-line"></div>
        <button class="split-dock-toggle" data-act="open-split" title="Настроить раздельное туннелирование">
          <span>Раздельное туннелирование</span>
          <span class="split-chip-label ${p.config?.split_sites?.length ? "active" : ""}">${splitSummary(p)}</span>
        </button>
        ${p.source === "ssh" ? `
        <div class="card-inner-split-line"></div>
        <button class="split-dock-toggle" data-manage-server="${p.id}" title="Параметры VPS, смена SNI, обнуление">
          <span>Управление VPS (SNI, сброс)</span>
          <span class="split-chip-label active" style="display:inline-flex; align-items:center; gap:4px;">${I.sliders} Настроить</span>
        </button>` : ""}
      </div>`;
  } else {
    serverCardHtml = `
      <div class="server-dock-card">
        <button class="server-dock-main" data-act="open-add-key">
          <div class="country-iso-tag">+</div>
          <div class="server-title-group">
            <div class="server-title-name">Добавить сервер</div>
            <div class="server-title-stats">Вставьте готовый ключ или разверните свой VPS</div>
          </div>
          <div class="card-chev-icon">${I.chev}</div>
        </button>
      </div>`;
  }

  return `
    ${renderTitlebar()}
    <div class="content-body">
      <div class="page-scroll view-home">
        <div class="dial-zone">
          ${dialButton}
          <div class="dial-metrics">
            <div class="status-badge-text ${statusClass}">${statusText}</div>
            ${timerHtml}
            ${detailHtml}
          </div>
        </div>
        ${serverCardHtml}
      </div>
    </div>
    ${renderBottomNav("home")}`;
}

// Экран серверов (Servers)
function renderServersView() {
  const selId = selectedProfile()?.id;
  const rows = state.data.profiles.length
    ? state.data.profiles
        .map((p) => {
          const ms = pingOf(p);
          const pingText = ms != null ? `${ms} ms` : "…";
          const dotClass = pingDotClass(ms);
          const isSel = p.id === selId;
          const code = countryCodeOf(p);
          return `
            <div class="server-row-panel ${isSel ? "selected" : ""}">
              <button class="server-select-action" data-select-server="${p.id}">
                <div class="radio-indicator"></div>
                <div class="country-iso-tag">${esc(code)}</div>
                <div class="server-title-group">
                  <div class="server-title-name">${esc(p.name)}</div>
                  <div class="server-title-stats">
                    <span>${esc(p.config?.server_host || "Сервер")}</span>
                    <span class="stat-separator"></span>
                    <span class="latency-meter">
                      <span class="latency-dot ${dotClass}"></span>
                      ${pingText}
                    </span>
                    <span class="stat-separator"></span>
                    <span style="font-size:10.5px; opacity:0.75;">${p.config?.enable_ipv6 ? "IPv4+6" : "IPv4"}</span>
                  </div>
                </div>
              </button>
              ${p.source === "ssh" ? `<button class="row-action-btn" data-manage-server="${p.id}" title="Управление сервером">${I.sliders}</button>` : ""}
              <button class="row-action-btn danger" data-delete-server="${p.id}" title="Удалить">${I.trash}</button>
            </div>`;
        })
        .join("")
    : `
      <div class="empty-placeholder">
        ${I.servers}
        <p>Список серверов пуст. Добавьте ключ или разверните собственный VPN-сервер.</p>
      </div>`;

  return `
    ${renderTitlebar()}
    <div class="content-body">
      <div class="page-scroll">
        <div class="section-head">
          <div>
            <h1>Серверы</h1>
            <p>Доступные профили и локации</p>
          </div>
        </div>
        <div class="servers-stack">${rows}</div>
        <div class="servers-footer-grid">
          <button class="solid-btn primary" data-act="open-add-key">${I.plus} Ключ доступа</button>
          <button class="solid-btn secondary" data-act="open-deploy">${I.terminal} Развернуть VPS</button>
        </div>
      </div>
    </div>
    ${renderBottomNav("servers")}`;
}

// Экран управления сервером (Server Manage)
function renderServerManageView() {
  const p = state.data.profiles.find((x) => x.id === state.managingServerId) || ownServer();
  if (!p) {
    state.route = "servers";
    return renderServersView();
  }

  const currentSni = state.manageSniDraft || p.config?.reality_sni || p.config?.sni || "www.microsoft.com";
  const hasPassword = Boolean(p.ssh_password_secret);
  const hasKey = Boolean(p.ssh_key_path);
  const credStatusText = hasPassword
    ? "SSH-пароль сохранен"
    : hasKey
    ? "SSH-ключ сохранен"
    : "Реквизиты не заданы";
  const credBadgeClass = hasPassword || hasKey ? "active" : "warning";

  const pingMs = pingOf(p);
  const pingText = pingMs != null ? `${pingMs} ms` : "проверка...";

  const sniPresets = ["microsoft.com", "apple.com", "google.com", "samsung.com", "vk.com", "amazon.com"];
  const sniChips = sniPresets
    .map(
      (d) => `
        <button class="quick-chip ${currentSni === d ? "selected" : ""}" data-set-manage-sni="${d}">
          ${d}
        </button>`
    )
    .join("");

  const isLoadingSni = state.manageLoading === "sni";
  const isLoadingReset = state.manageLoading === "reset";
  const isLoadingUpdate = state.manageLoading === "update";
  const isLoadingCheck = state.manageLoading === "check";
  const isLoadingCred = state.manageLoading === "save-cred";

  const serverVer = p.server_version || "0.1.0";
  const clientVer = state.data.version || "0.1.0";
  const needsUpdate = Boolean(p.needs_update || (p.server_version && p.server_version !== clientVer));

  // Предупреждающий баннер, если реквизиты не заданы
  const warningBanner = (!hasPassword && !hasKey)
    ? `
      <div class="manage-warning-banner">
        <div class="manage-warning-icon">${I.alert}</div>
        <div class="manage-warning-body">
          <div class="manage-warning-title">Реквизиты SSH не настроены</div>
          <div class="manage-warning-desc">Для применения параметров и команд укажите пароль или приватный SSH-ключ в блоке реквизитов ниже.</div>
        </div>
      </div>`
    : "";

  // Карточка обновления (показывает кнопку обновления только если требуется обновление)
  let updateCard = "";
  if (needsUpdate) {
    const updatePct = state.manageProgress?.pct || 0;
    const updateStage = state.manageProgress?.stage || "Обновление файлов сервера...";
    updateCard = `
      <div class="manage-section-card">
        <div class="manage-card-header-row">
          <div class="section-title-sm">Обновление ядра сервера</div>
          <span class="status-pill warning">Требуется обновление</span>
        </div>
        <div class="section-desc-sm">На сервере обнаружена устаревшая версия ядра (${esc(serverVer)}). Доступна версия v${esc(clientVer)}.</div>
        ${isLoadingUpdate ? `
          <div class="process-taskbar manage-taskbar" style="max-width:100%; margin-top:10px;">
            <div class="process-taskbar-meta">
              <span class="process-taskbar-stage">${esc(updateStage)}</span>
              <span class="process-taskbar-pct">${updatePct}%</span>
            </div>
            <div class="process-taskbar-track">
              <div class="process-taskbar-fill" style="width: ${Math.max(4, updatePct)}%;"></div>
            </div>
          </div>
        ` : `
          <button class="solid-btn primary block" data-act="update-manage-fw" style="margin-top:10px;">
            ${I.refresh} Обновить ядро сервера
          </button>
        `}
      </div>`;
  } else {
    updateCard = `
      <div class="manage-section-card">
        <div class="manage-card-header-row">
          <div class="section-title-sm">Ядро сервера</div>
          <span class="status-pill success">Актуально (v${esc(serverVer)})</span>
        </div>
        <div class="section-desc-sm">Установлена актуальная версия ядра VPN. Обновление не требуется.</div>
        <button class="solid-btn secondary block" data-act="check-manage-version" ${isLoadingCheck ? "disabled" : ""} style="margin-top:10px;">
          ${isLoadingCheck ? "Проверка версии..." : `${I.refresh} Проверить обновления`}
        </button>
      </div>`;
  }

  // Данные для формы реквизитов
  const creds = state.manageCreds || {
    auth: p.ssh_auth || (p.ssh_key_path ? "key" : "password"),
    keyPath: p.ssh_key_path || "",
    keyLabel: p.ssh_key_path ? p.ssh_key_path.split(/[/\\]/).pop() : "",
    showPassword: false,
  };
  const authType = creds.auth || "password";
  const passType = creds.showPassword ? "text" : "password";

  const credsAuthFields =
    authType === "key"
      ? `
        <div class="input-block" style="margin-top:8px;">
          <div class="input-caption">Файл приватного SSH-ключа</div>
          <button class="solid-btn secondary block" data-act="pick-manage-ssh-key" style="justify-content:flex-start; text-align:left; font-family:JetBrainsMono; font-size:11.5px;">
            ${creds.keyLabel ? `${I.key} ${esc(creds.keyLabel)}` : "Выбрать ключ (.pem, .key, id_rsa)..."}
          </button>
          ${creds.keyPath ? `<div style="font-size:10.5px; color:var(--text-dim); margin-top:3px; font-family:JetBrainsMono; word-break:break-all;">${esc(creds.keyPath)}</div>` : ""}
        </div>
        <div class="input-block" style="margin-top:8px;">
          <div class="input-caption">Или вставьте текст ключа</div>
          <textarea id="manage-cred-rawkey" class="text-multiline" rows="3" placeholder="-----BEGIN OPENSSH PRIVATE KEY-----..." spellcheck="false"></textarea>
        </div>`
      : `
        <div class="input-block" style="margin-top:8px;">
          <div class="input-caption">Пароль пользователя ${esc(p.ssh_user || "root")}</div>
          <div class="input-with-action">
            <input type="${passType}" class="text-input" id="manage-cred-pass" placeholder="${hasPassword ? "•••••••••••• (введите для изменения)" : "Введите пароль root"}" autocomplete="off" spellcheck="false" />
            <button class="input-inline-btn" data-act="toggle-manage-password" title="${creds.showPassword ? "Скрыть" : "Показать"}">
              ${creds.showPassword ? I.eyeOff : I.eye}
            </button>
          </div>
          ${hasPassword ? `<div style="font-size:11px; color:var(--accent-hover); margin-top:3px;">Пароль сохранен</div>` : `<div style="font-size:11px; color:var(--danger); margin-top:3px;">Пароль не задан</div>`}
        </div>`;

  return `
    ${renderTitlebar({ back: true, title: "Управление VPS" })}
    <div class="content-body">
      <div class="page-scroll">
        ${warningBanner}
        <div class="server-manage-hero">
          <div class="hero-top-row">
            <div class="country-iso-tag">VPS</div>
            <div style="flex:1; min-width:0;">
              <div class="server-title-name" style="font-size:15px;">${esc(p.name)}</div>
              <div class="server-title-stats">
                <span>${esc(p.ssh_user || "root")}@${esc(p.ssh_host || p.config?.server_host || "Server")}:${p.ssh_port || 22}</span>
                <span class="stat-separator"></span>
                <span>${pingText}</span>
              </div>
            </div>
          </div>
          <div class="hero-badges-row">
            <span class="security-chip ${credBadgeClass}">
              ${I.lock} ${credStatusText}
            </span>
            <span class="security-chip active">
              REALITY :443
            </span>
            <span class="security-chip ${p.config?.enable_ipv6 ? "active" : ""}">
              ${p.config?.enable_ipv6 ? "Dual-Stack IPv6" : "Чистый IPv4"}
            </span>
          </div>
        </div>

        <!-- 1. Маскировка SNI -->
        <div class="manage-section-card">
          <div class="section-title-sm">Маскировка SNI (Обход блокировок)</div>
          <div class="section-desc-sm">Сайт, под который маскируется VPN-трафик. Изменяется на лету на удаленном сервере без ввода пароля.</div>
          <div class="input-form-box" style="margin-top:8px;">
            <input type="text" class="text-input mono" id="manage-sni-input" value="${esc(currentSni)}" placeholder="www.microsoft.com" autocomplete="off" spellcheck="false" />
          </div>
          <div class="quick-chips-wrap" style="margin-top:8px;">
            ${sniChips}
          </div>
          <button class="solid-btn primary block" data-act="apply-manage-sni" ${isLoadingSni ? "disabled" : ""} style="margin-top:10px;">
            ${isLoadingSni ? "Обновление SNI на сервере..." : "Применить новый SNI"}
          </button>
        </div>

        <!-- Сетевой протокол (IPv4 / IPv6 Dual-Stack) -->
        <div class="manage-section-card">
          <div class="manage-card-header-row">
            <div class="section-title-sm">Сетевой стек и протокол</div>
            <span class="status-pill ${p.config?.enable_ipv6 ? "success" : "neutral"}">
              ${p.config?.enable_ipv6 ? "Dual-Stack (IPv4 + IPv6)" : "Чистый IPv4 (370+ Мбит/с)"}
            </span>
          </div>
          <div class="section-desc-sm">
            ${p.config?.enable_ipv6
              ? "Активен стек IPv4 + IPv6 с MSS 1280. Если провайдер замедляет или дропает IPv6-маршруты, отключите IPv6 для максимальной скорости 370+ Мбит/с."
              : "Трафик идет исключительно через чистый IPv4. Обеспечивает наивысшую скорость (370+ Мбит/с) и минимальный пинг на российских провайдерах."}
          </div>
          <button class="solid-btn secondary block" data-act="toggle-manage-ipv6" style="margin-top:10px;">
            ${p.config?.enable_ipv6 ? "Переключить на чистый IPv4 (Макс. скорость)" : "Включить IPv6 (Dual-Stack)"}
          </button>
        </div>

        <!-- 2. Обновление ядра (перемещено ВЫШЕ сброса, кнопка только при необходимости) -->
        ${updateCard}

        <!-- 3. Обнуление и сброс сервера (перемещено НИЖЕ обновления) -->
        <div class="manage-section-card">
          <div class="section-title-sm">Обнуление и сброс сервера</div>
          <div class="section-desc-sm">Стирает все выданные клиентские ключи, пересоздает мастер-ключи шифрования сервера и выпускает новый чистый ключ владельца. Доступ по SSH выполняется автоматически по сохраненным данным.</div>
          ${isLoadingReset ? `
            <div class="process-taskbar manage-taskbar" style="max-width:100%; margin-top:10px;">
              <div class="process-taskbar-meta">
                <span class="process-taskbar-stage">${esc(state.manageProgress?.stage || "Генерация новых ключей и перезапуск...")}</span>
                <span class="process-taskbar-pct">${state.manageProgress?.pct || 0}%</span>
              </div>
              <div class="process-taskbar-track">
                <div class="process-taskbar-fill" style="width: ${Math.max(4, state.manageProgress?.pct || 0)}%;"></div>
              </div>
            </div>
          ` : `
            <button class="solid-btn danger-outline block" data-act="open-reset-confirm" style="margin-top:10px;">
              ${I.trash} Обнулить сервер
            </button>
          `}
        </div>

        <!-- 4. Реквизиты SSH подключения -->
        <div class="manage-section-card">
          <div class="section-title-sm">Реквизиты SSH подключения</div>
          <div class="section-desc-sm">Параметры удаленного хоста для автоматического управления сервером.</div>
          <div class="input-block" style="margin-top:10px;">
            <div class="input-caption">IP-адрес или домен</div>
            <input type="text" class="text-input mono" id="manage-cred-host" value="${esc(p.ssh_host || p.config?.server_host || "")}" placeholder="123.45.67.89" />
          </div>
          <div style="display:grid; grid-template-columns:1fr 1fr; gap:8px; margin-top:8px;">
            <div class="input-block">
              <div class="input-caption">Пользователь</div>
              <input type="text" class="text-input" id="manage-cred-user" value="${esc(p.ssh_user || "root")}" />
            </div>
            <div class="input-block">
              <div class="input-caption">SSH порт</div>
              <input type="text" class="text-input mono" id="manage-cred-port" value="${esc(String(p.ssh_port || 22))}" />
            </div>
          </div>
          <div class="input-block" style="margin-top:8px;">
            <div class="input-caption">Тип аутентификации</div>
            <div class="segment-bar">
              <button class="segment-item-btn ${authType === "password" ? "active" : ""}" data-cred-auth="password">Пароль</button>
              <button class="segment-item-btn ${authType === "key" ? "active" : ""}" data-cred-auth="key">SSH-ключ</button>
            </div>
          </div>
          ${credsAuthFields}
          <button class="solid-btn primary block" data-act="save-manage-credentials" ${isLoadingCred ? "disabled" : ""} style="margin-top:12px;">
            ${isLoadingCred ? "Сохранение..." : `${I.check} Сохранить реквизиты SSH`}
          </button>
        </div>
      </div>
    </div>
    ${renderBottomNav("servers")}`;
}

// Экран доступа и раздачи ключей (Access)
function renderAccessView() {
  const hasOwn = state.data.profiles.some((p) => p.source === "ssh");
  const keysList = state.data.issued.length
    ? state.data.issued
        .map((k) => {
          const daysText = k.days ? `${k.days} дн.` : "Бессрочно";
          return `
            <div class="issued-key-card" data-show-key="${k.id}">
              <div>
                <div class="server-title-name">${esc(k.name)}</div>
                <div class="key-tech-row">${esc(k.server_code)} · Устройств: ${k.devices} · Срок: ${daysText}</div>
              </div>
              <div class="card-chev-icon">${I.chev}</div>
            </div>`;
        })
        .join("")
    : `
      <div class="empty-placeholder">
        ${I.key}
        <p>Нет выданных ключей. Нажмите кнопку ниже для генерации нового доступа.</p>
      </div>`;

  const overview = `
    <div class="access-overview-panel">
      <div class="overview-metric">
        <div class="metric-number">${state.data.issued.length}</div>
        <div class="metric-label">Ключей</div>
      </div>
      <div class="overview-separator"></div>
      <div class="overview-metric">
        <div class="metric-number">${state.data.profiles.filter((p) => p.source === "ssh").length}</div>
        <div class="metric-label">Серверов</div>
      </div>
    </div>`;

  const body = hasOwn
    ? `
      ${overview}
      <div class="issued-keys-stack">${keysList}</div>
      <div style="display:flex; flex-direction:column; gap:6px; padding-top:10px; flex-shrink:0;">
        <button class="solid-btn primary block" data-act="open-issue-form">${I.plus} Создать новый ключ</button>
        <button class="solid-btn secondary block" data-act="open-manage-vps">${I.sliders} Управление сервером (SNI / Сброс)</button>
      </div>`
    : `
      <div class="empty-placeholder" style="flex:1; justify-content:center;">
        ${I.terminal}
        <div style="font-size:14px; font-weight:700; color:var(--text); margin-top:4px;">Собственные серверы</div>
        <p>В этом разделе создаются и отзываются ключи доступа для ваших серверов, развернутых через приложение.</p>
        <button class="solid-btn primary" data-act="open-deploy" style="margin-top:8px;">${I.terminal} Развернуть сервер</button>
      </div>`;

  return `
    ${renderTitlebar()}
    <div class="content-body">
      <div class="page-scroll">
        <div class="section-head">
          <div>
            <h1>Доступ</h1>
            <p>Выдача и контроль ключей</p>
          </div>
        </div>
        ${body}
      </div>
    </div>
    ${renderBottomNav("access")}`;
}

// Экран настроек (Settings)
function renderSettingsView() {
  const s = state.data.settings;
  const toggle = (key, val) => `
    <button class="switch-control ${val ? "active" : ""}" data-toggle-setting="${key}">
      <div class="switch-nub"></div>
    </button>`;

  return `
    ${renderTitlebar()}
    <div class="content-body">
      <div class="page-scroll">
        <div class="section-head">
          <div>
            <h1>Настройки</h1>
            <p>Параметры работы и безопасность</p>
          </div>
        </div>

        <div class="settings-section-title">Система и запуск</div>
        <div class="settings-list-box">
          <div class="settings-entry-row">
            <div>
              <div class="entry-label-head">Запуск при входе</div>
              <div class="entry-label-sub">Стартовать вместе с Windows</div>
            </div>
            ${toggle("autostart", s.autostart)}
          </div>
          <div class="settings-entry-row">
            <div>
              <div class="entry-label-head">Сворачивать в трей</div>
              <div class="entry-label-sub">Оставлять в области уведомлений при закрытии</div>
            </div>
            ${toggle("minimize_to_tray", s.minimize_to_tray)}
          </div>
          <div class="settings-entry-row">
            <div>
              <div class="entry-label-head">Аварийная блокировка (Kill Switch)</div>
              <div class="entry-label-sub">Блокировать трафик при разрыве соединения</div>
            </div>
            ${toggle("kill_switch", s.kill_switch)}
          </div>
        </div>

        <div class="settings-section-title">Идентификация и протокол</div>
        <div class="settings-list-box">
          <div class="settings-entry-row">
            <div>
              <div class="entry-label-head">ID устройства</div>
              <div class="entry-label-sub">Уникальный маркер оборудования</div>
            </div>
            <button class="copyable-mono-btn" data-copy-text="${esc(state.data.device_id)}" title="Копировать">
              <span>${esc(state.data.device_id)}</span>
              ${I.copy}
            </button>
          </div>
          <div class="settings-entry-row">
            <div>
              <div class="entry-label-head">Версия клиента</div>
              <div class="entry-label-sub">Obsidian Protocol v2.0 (REALITY / UDP)</div>
            </div>
            <span class="copyable-mono-btn" style="cursor:default">${esc(state.data.version)}</span>
          </div>
        </div>
      </div>
    </div>
    ${renderBottomNav("settings")}`;
}

// Мастер развертывания сервера
function renderDeployStep1() {
  const d = state.deploy;
  const isUpdate = d.kind === "update";
  const title = isUpdate ? "Обновление прошивки" : "Развертывание сервера";
  const authBlock =
    d.auth === "key"
      ? `
        <div class="input-block">
          <div class="input-caption">Приватный SSH ключ</div>
          <button class="solid-btn secondary block" data-act="pick-deploy-ssh-key" style="justify-content:flex-start;">
            ${d.keyLabel || "Выбрать файл ключа (.pem, .key)..."}
          </button>
        </div>`
      : `
        <div class="input-block">
          <div class="input-caption">Пароль root</div>
          <input id="ssh-pass" class="text-input" type="password" placeholder="Пароль от сервера" value="${esc(d.password || "")}"/>
        </div>`;

  return `
    ${renderTitlebar({ back: true, title })}
    <div class="content-body">
      <div class="page-scroll">
        <div class="wizard-steps-line">
          <div class="wizard-step-dash active"></div>
          <div class="wizard-step-dash"></div>
          <div class="wizard-step-dash"></div>
        </div>
        <div class="section-head">
          <div>
            <h1>${isUpdate ? "Параметры VPS" : "Свой сервер за 2 минуты"}</h1>
            <p>Чистая Ubuntu 22.04 / 24.04 или Debian 12 с root-доступом</p>
          </div>
        </div>
        <div class="input-block">
          <div class="input-caption">IP-адрес сервера</div>
          <input id="ssh-host" class="text-input" placeholder="203.0.113.42" value="${esc(d.host || "")}"/>
        </div>
        <div style="display:grid; grid-template-columns:1fr 1fr; gap:8px;">
          <div class="input-block">
            <div class="input-caption">Пользователь</div>
            <input id="ssh-user" class="text-input" value="${esc(d.user || "root")}"/>
          </div>
          <div class="input-block">
            <div class="input-caption">SSH порт</div>
            <input id="ssh-port" class="text-input" value="${esc(d.port || "22")}"/>
          </div>
        </div>
        <div class="input-block">
          <div class="input-caption">Маскировка (SNI домен)</div>
          <input id="ssh-mask" class="text-input" placeholder="www.microsoft.com" value="${esc(d.mask || "www.microsoft.com")}"/>
        </div>
        <div class="input-block">
          <div class="input-caption">Аутентификация</div>
          <div class="segment-bar">
            <button class="segment-item-btn ${d.auth === "password" ? "active" : ""}" data-deploy-auth="password">Пароль</button>
            <button class="segment-item-btn ${d.auth === "key" ? "active" : ""}" data-deploy-auth="key">SSH-ключ</button>
          </div>
        </div>
        ${authBlock}
        <div style="flex:1"></div>
        <div style="padding-top:10px">
          <button class="solid-btn primary block" data-act="start-deploy-run">Начать установку</button>
        </div>
      </div>
    </div>`;
}

function renderDeployStep2() {
  const d = state.deploy;
  return `
    ${renderTitlebar({ back: false, title: "Установка..." })}
    <div class="content-body">
      <div class="page-scroll">
        <div class="wizard-steps-line">
          <div class="wizard-step-dash"></div>
          <div class="wizard-step-dash active"></div>
          <div class="wizard-step-dash"></div>
        </div>
        <div class="section-head">
          <div>
            <h1>Настройка сервера</h1>
            <p>Установка Docker, конфигурация NAT и ключей REALITY</p>
          </div>
        </div>
        <div class="process-taskbar deploy-taskbar" style="max-width:100%; margin:8px 0 12px;">
          <div class="process-taskbar-meta">
            <span class="process-taskbar-stage deploy-taskbar-stage">Установка компонентов и настройка REALITY...</span>
            <span class="process-taskbar-pct deploy-taskbar-pct">${d.progress || 0}%</span>
          </div>
          <div class="process-taskbar-track">
            <div class="process-taskbar-fill deploy-taskbar-fill" style="width:${Math.max(4, d.progress || 0)}%"></div>
          </div>
        </div>
        <div class="terminal-console-box" id="deploy-terminal">${esc(d.log || "Инициализация SSH-сессии...\n")}</div>
        <div style="flex:1"></div>
        <div style="padding-top:10px">
          <button class="solid-btn secondary block" disabled>Пожалуйста, подождите...</button>
        </div>
      </div>
    </div>`;
}

function renderDeployStep3() {
  const d = state.deploy;
  const isUpdate = d.kind === "update";
  if (isUpdate) {
    return `
      ${renderTitlebar({ back: true, title: "Готово" })}
      <div class="content-body">
        <div class="page-scroll">
          <div class="wizard-steps-line">
            <div class="wizard-step-dash"></div>
            <div class="wizard-step-dash"></div>
            <div class="wizard-step-dash active"></div>
          </div>
          <div class="empty-placeholder" style="margin-top:20px;">
            <div style="color:var(--success);">${I.check}</div>
            <div style="font-size:15px; font-weight:700; color:var(--text); margin-top:6px;">Прошивка обновлена</div>
            <p>Сервер переведен на маскировку REALITY на порту 443. Старые ключи сохранены.</p>
            <div style="margin-top:8px;">
              <span class="status-pill ${d.result?.enable_ipv6 ? "success" : "neutral"}">
                ${d.result?.enable_ipv6 ? "IPv4 + IPv6 (Dual-Stack)" : "Чистый IPv4 (370+ Мбит/с)"}
              </span>
            </div>
          </div>
          <div style="flex:1"></div>
          <button class="solid-btn primary block" data-act="deploy-finish">Готово</button>
        </div>
      </div>`;
  }

  const r = d.result || {};
  const shareKey = r.share || r.key || "";
  return `
    ${renderTitlebar({ back: true, title: "Сервер готов" })}
    <div class="content-body">
      <div class="page-scroll">
        <div class="wizard-steps-line">
          <div class="wizard-step-dash"></div>
          <div class="wizard-step-dash"></div>
          <div class="wizard-step-dash active"></div>
        </div>
        <div class="section-head">
          <div>
            <h1>Сервер успешно запущен</h1>
            <p>Профиль добавлен в список ваших локаций</p>
          </div>
        </div>
        <div class="settings-list-box" style="margin-bottom:10px;">
          <div class="settings-entry-row">
            <div>
              <div class="entry-label-head">Ключ подключения</div>
              <div class="entry-label-sub" style="font-family:JetBrainsMono;">${esc(shareKey.slice(0, 30))}...</div>
            </div>
            <button class="solid-btn secondary" data-copy-text="${esc(shareKey)}">${I.copy} Копировать</button>
          </div>
          <div class="settings-entry-row">
            <div>
              <div class="entry-label-head">Сетевой протокол</div>
              <div class="entry-label-sub">${r.enable_ipv6 ? "Dual-Stack: автоопределен рабочий IPv6 на VPS" : "Чистый IPv4: максимальная скорость 370+ Мбит/с"}</div>
            </div>
            <span class="status-pill ${r.enable_ipv6 ? "success" : "neutral"}">${r.enable_ipv6 ? "IPv4+6" : "IPv4"}</span>
          </div>
          ${r.admin_token ? `
            <div class="settings-entry-row">
              <div>
                <div class="entry-label-head">Токен администратора</div>
                <div class="entry-label-sub" style="color:var(--warning)">Сохраните его прямо сейчас, он не сохраняется в открытом виде!</div>
              </div>
              <button class="solid-btn secondary" data-copy-text="${esc(r.admin_token)}">${I.copy}</button>
            </div>` : ""}
        </div>
        <div style="flex:1"></div>
        <button class="solid-btn primary block" data-act="deploy-finish">Готово</button>
      </div>
    </div>`;
}

// Форма выпуска ключа
function renderIssueFormView() {
  const d = state.issue;
  const chip = (days, label) => `
    <button class="preset-tag-btn ${d.days === days ? "active" : ""}" data-issue-days="${days}">${label}</button>`;

  return `
    ${renderTitlebar({ back: true, title: "Выпуск ключа" })}
    <div class="content-body">
      <div class="page-scroll">
        <div class="section-head">
          <div>
            <h1>Новый ключ доступа</h1>
            <p>Параметры создаваемого профиля</p>
          </div>
        </div>
        <div class="input-block">
          <div class="input-caption">Имя или назначение</div>
          <input id="issue-name" class="text-input" placeholder="Телефон, Ноутбук, Семья" value="${esc(d.name)}"/>
        </div>
        <div class="input-block">
          <div class="input-caption">Срок действия</div>
          <div class="preset-tag-row">
            ${chip(7, "7 дней")}
            ${chip(30, "30 дней")}
            ${chip(90, "90 дней")}
            ${chip(0, "Бессрочно")}
          </div>
        </div>
        <div class="input-block">
          <div class="input-caption">Лимит одновременных устройств</div>
          <div class="counter-stepper">
            <button class="counter-btn" data-act="dev-minus">−</button>
            <span class="counter-display">${d.devices}</span>
            <button class="counter-btn" data-act="dev-plus">+</button>
          </div>
        </div>
        <div style="flex:1"></div>
        <div style="padding-top:10px">
          <button class="solid-btn primary block" data-act="submit-issue-key">Создать ключ</button>
        </div>
      </div>
    </div>`;
}

// Экран с QR-кодом созданного ключа
function renderIssuedResultView() {
  const k = state.issue.made;
  return `
    ${renderTitlebar({ back: true, title: "Ключ доступа" })}
    <div class="content-body">
      <div class="page-scroll" style="align-items:center;">
        <div class="section-head" style="width:100%;">
          <div>
            <h1>Ключ готов к отправке</h1>
            <p>${esc(k?.name || "Гость")} · ${esc(k?.server_code || "")}</p>
          </div>
        </div>
        <div class="qr-square-frame">${state.issue.qr || ""}</div>
        <div style="font-family:JetBrainsMono; font-size:10.5px; color:var(--text-dim); word-break:break-all; text-align:center; max-width:320px; margin:6px 0 14px;">
          ${esc(k?.key || "")}
        </div>
        <div style="flex:1"></div>
        <div style="width:100%; display:grid; grid-template-columns:1fr 1fr; gap:8px;">
          <button class="solid-btn secondary" data-copy-server-uri="${esc(k?.server_id || "")}">${I.copy} Ссылка (URI)</button>
          <button class="solid-btn primary" data-copy-text="${esc(k?.key || "")}">${I.copy} Ключ (OBSDN)</button>
        </div>
      </div>
    </div>`;
}

// Модалка добавления ключа
function renderAddKeyModal() {
  const hint = state.keyHint
    ? `<div style="font-size:11.5px; margin-top:4px; color:${state.keyHint.ok ? "var(--accent-hover)" : "var(--danger)"}">${esc(state.keyHint.text)}</div>`
    : "";

  return `
    <div class="sheet-backdrop ${state.modal === "add-key" ? "open" : ""}" data-act="close-modal">
      <div class="sheet-modal-box" data-stop-propagation>
        <div class="sheet-drag-handle"></div>
        <div class="sheet-header-line">
          <div class="sheet-title-text">Добавить сервер по ссылке или ключу</div>
          <button class="row-action-btn" data-act="paste-key-clipboard" title="Вставить из буфера">${I.paste}</button>
        </div>
        <div class="sheet-content-scroll">
          <div class="input-block">
            <div class="input-caption">Ссылка (obsidian://, vpn://) или ключ (OBSDN-...)</div>
            <textarea id="key-input" class="text-multiline" rows="3" placeholder="Вставьте ссылку obsidian://, vpn:// или ключ OBSDN-..." spellcheck="false">${esc(state.keyDraft)}</textarea>
            ${hint}
          </div>
        </div>
        <div class="sheet-footer-actions">
          <button class="solid-btn secondary" data-act="close-modal">Отмена</button>
          <button class="solid-btn primary" data-act="save-key-action">Добавить</button>
        </div>
      </div>
    </div>`;
}

// Модалка раздельного туннелирования
function renderSplitModal() {
  const p = selectedProfile();
  const sites = (p?.config?.split_sites || []).join("\n");
  const draft = state.splitDraft || sites;

  return `
    <div class="sheet-backdrop ${state.modal === "split" ? "open" : ""}" data-act="close-modal">
      <div class="sheet-modal-box" data-stop-propagation>
        <div class="sheet-drag-handle"></div>
        <div class="sheet-header-line">
          <div>
            <div class="sheet-title-text">Раздельное туннелирование</div>
            <div style="font-size:11px; color:var(--text-dim); margin-top:1px;">Сайты из списка открываются напрямую без VPN</div>
          </div>
        </div>
        <div class="sheet-content-scroll">
          <div class="preset-tag-row">
            <button class="preset-tag-btn" data-add-preset="gosuslugi">Госуслуги и банки</button>
            <button class="preset-tag-btn" data-add-preset="ru-media">VK, Яндекс, Кинопоиск</button>
            <button class="preset-tag-btn" data-add-preset="ru-all">Зона *.ru</button>
            <button class="preset-tag-btn" data-add-preset="clear" style="color:var(--danger)">Очистить</button>
          </div>
          <div class="input-block">
            <div class="input-caption">Список доменов (по одному на строку)</div>
            <textarea id="split-input" class="text-multiline" rows="5" placeholder="gosuslugi.ru&#10;sberbank.ru&#10;kinopoisk.ru">${esc(draft)}</textarea>
          </div>
        </div>
        <div class="sheet-footer-actions">
          <button class="solid-btn secondary" data-act="close-modal">Отмена</button>
          <button class="solid-btn primary" data-act="save-split-action">Сохранить</button>
        </div>
      </div>
    </div>`;
}

// Модалка подтверждения удаления
function renderConfirmDeleteModal() {
  const p = state.deleteCandidate;
  return `
    <div class="sheet-backdrop ${state.modal === "confirm-delete" ? "open" : ""}" data-act="close-modal">
      <div class="sheet-modal-box" data-stop-propagation>
        <div class="sheet-drag-handle"></div>
        <div class="sheet-header-line">
          <div class="sheet-title-text">Удалить сервер?</div>
        </div>
        <div class="sheet-content-scroll">
          <div style="font-size:13px; color:var(--text-secondary); line-height:1.4;">
            Вы уверены, что хотите удалить профиль <b>${esc(p?.name || "сервера")}</b>?
            ${p?.source === "ssh" ? "<br/><span style='color:var(--warning); font-size:11.5px;'>Это ваш личный VPS. Выданные для него ключи также перестанут работать.</span>" : ""}
          </div>
        </div>
        <div class="sheet-footer-actions">
          <button class="solid-btn secondary" data-act="close-modal">Отмена</button>
          <button class="solid-btn danger" data-act="confirm-delete-action">Удалить</button>
        </div>
      </div>
    </div>`;
}

// Модалка подтверждения обнуления сервера
function renderConfirmResetModal() {
  const p = state.data.profiles.find((x) => x.id === state.managingServerId) || ownServer();
  const host = p?.ssh_host || p?.config?.server_host || "VPS";
  return `
    <div class="sheet-backdrop ${state.modal === "confirm-reset" ? "open" : ""}" data-act="close-modal">
      <div class="sheet-modal-box" data-stop-propagation>
        <div class="sheet-drag-handle"></div>
        <div class="sheet-header-line">
          <div class="sheet-title-text" style="color:var(--danger)">Обнулить сервер?</div>
        </div>
        <div class="sheet-content-scroll">
          <div style="font-size:12.5px; color:var(--text-secondary); line-height:1.45;">
            Сервер <b>${esc(host)}</b> будет полностью сброшен. Все выданные клиентские доступы будут удалены, криптографические ключи сервера пересозданы, а вам будет выдан единственный обновленный ключ владельца.
            <div style="font-size:11.5px; color:var(--text-dim); margin-top:8px;">
              Подключение выполняется автоматически по сохраненным SSH-данным без запроса пароля.
            </div>
          </div>
        </div>
        <div class="sheet-footer-actions">
          <button class="solid-btn secondary" data-act="close-modal">Отмена</button>
          <button class="solid-btn danger" data-act="confirm-reset-action">Да, обнулить сервер</button>
        </div>
      </div>
    </div>`;
}

// ==================== РЕНДЕР ====================

function render() {
  const root = document.getElementById("app");
  if (!root) return;

  let body = "";
  if (state.route === "home") body = renderHomeView();
  else if (state.route === "servers") body = renderServersView();
  else if (state.route === "server-manage") body = renderServerManageView();
  else if (state.route === "access") body = renderAccessView();
  else if (state.route === "settings") body = renderSettingsView();
  else if (state.route === "deploy") {
    body = state.deploy.step === 1 ? renderDeployStep1() : state.deploy.step === 2 ? renderDeployStep2() : renderDeployStep3();
  } else if (state.route === "issue") body = renderIssueFormView();
  else if (state.route === "issued") body = renderIssuedResultView();
  else body = renderHomeView();

  const sheets = `
    ${renderAddKeyModal()}
    ${renderSplitModal()}
    ${renderConfirmDeleteModal()}
    ${renderConfirmResetModal()}`;

  root.innerHTML = `<div class="app-window">${body}${sheets}</div>`;
  bindLiveInputs();
}

// Привязка живых полей ввода
function bindLiveInputs() {
  const keyInput = document.getElementById("key-input");
  if (keyInput) {
    keyInput.addEventListener("input", async () => {
      state.keyDraft = keyInput.value;
      const v = keyInput.value.trim();
      if (!v) {
        state.keyHint = null;
        updateKeyHintDOM();
        return;
      }
      try {
        const summary = await invoke("decode_preview", { key: v });
        state.keyHint = { ok: true, text: `Распознано: ${summary}` };
      } catch (err) {
        state.keyHint = { ok: false, text: String(err) };
      }
      updateKeyHintDOM();
    });
  }
}

function updateKeyHintDOM() {
  const box = document.getElementById("key-input")?.parentElement;
  if (!box) return;
  let hintEl = box.querySelector(".key-hint-rendered");
  if (!state.keyHint) {
    if (hintEl) hintEl.remove();
    return;
  }
  if (!hintEl) {
    hintEl = document.createElement("div");
    hintEl.className = "key-hint-rendered";
    hintEl.style.fontSize = "11.5px";
    hintEl.style.marginTop = "4px";
    box.appendChild(hintEl);
  }
  hintEl.style.color = state.keyHint.ok ? "var(--accent-hover)" : "var(--danger)";
  hintEl.textContent = state.keyHint.text;
}

function saveDeployInputs() {
  state.deploy.host = document.getElementById("ssh-host")?.value || state.deploy.host || "";
  state.deploy.user = document.getElementById("ssh-user")?.value || state.deploy.user || "root";
  state.deploy.port = document.getElementById("ssh-port")?.value || state.deploy.port || "22";
  state.deploy.password = document.getElementById("ssh-pass")?.value || state.deploy.password || "";
  state.deploy.mask = document.getElementById("ssh-mask")?.value || state.deploy.mask || "www.microsoft.com";
}

function openDeployWizard(kind, profile = null) {
  const auth = profile?.ssh_auth || (profile?.ssh_key_path ? "key" : "password");
  state.deploy = {
    kind,
    step: 1,
    log: "",
    progress: 0,
    result: null,
    auth,
    keyPath: profile?.ssh_key_path || "",
    keyLabel: profile?.ssh_key_path ? `Ключ: ${profile.ssh_key_path.split(/[/\\]/).pop()}` : "",
    host: profile ? profile.ssh_host || profile.config?.server_host || "" : "",
    user: profile ? profile.ssh_user || "root" : "root",
    port: profile ? String(profile.ssh_port || 22) : "22",
    password: profile?.ssh_password_secret || "",
    mask: profile?.config?.reality_sni || "www.microsoft.com",
  };
  state.route = "deploy";
  render();
}

// ==================== ДЕЛЕГИРОВАНИЕ СОБЫТИЙ КЛИКА ====================

document.addEventListener("click", async (e) => {
  // Изоляция кликов внутри модалки
  if (e.target.closest("[data-stop-propagation]")) {
    e.stopPropagation();
  }

  // Переключение вкладок
  const navBtn = e.target.closest("[data-nav]");
  if (navBtn) {
    state.route = navBtn.dataset.nav;
    state.modal = null;
    render();
    return;
  }

  // Выбор сервера
  const selectBtn = e.target.closest("[data-select-server]");
  if (selectBtn) {
    const id = selectBtn.dataset.selectServer;
    try {
      state.data = await invoke("select_profile", { id });
      state.route = "home";
      showToast("Сервер выбран");
    } catch (err) {
      showToast(String(err), "error");
    }
    render();
    return;
  }

  // Управление сервером (VPS)
  const manageBtn = e.target.closest("[data-manage-server]");
  if (manageBtn) {
    state.managingServerId = manageBtn.dataset.manageServer;
    const p = state.data.profiles.find((x) => x.id === state.managingServerId);
    state.manageSniDraft = p?.config?.reality_sni || p?.config?.sni || "www.microsoft.com";
    state.manageCreds = {
      auth: p?.ssh_auth || (p?.ssh_key_path ? "key" : "password"),
      keyPath: p?.ssh_key_path || "",
      keyLabel: p?.ssh_key_path ? p.ssh_key_path.split(/[/\\]/).pop() : "",
      showPassword: false,
    };
    state.route = "server-manage";
    render();
    return;
  }

  // Быстрый выбор SNI в настройках сервера
  const setSniBtn = e.target.closest("[data-set-manage-sni]");
  if (setSniBtn) {
    const sni = setSniBtn.dataset.setManageSni;
    state.manageSniDraft = sni;
    const input = document.getElementById("manage-sni-input");
    if (input) input.value = sni;
    render();
    return;
  }

  // Переключение типа аутентификации в реквизитах сервера
  const credAuthBtn = e.target.closest("[data-cred-auth]");
  if (credAuthBtn) {
    if (!state.manageCreds) state.manageCreds = {};
    state.manageCreds.auth = credAuthBtn.dataset.credAuth;
    render();
    return;
  }

  // Обновление сервера
  const updateBtn = e.target.closest("[data-update-server]");
  if (updateBtn) {
    const p = ownServer(updateBtn.dataset.updateServer);
    if (p) openDeployWizard("update", p);
    return;
  }

  // Удаление сервера
  const delBtn = e.target.closest("[data-delete-server]");
  if (delBtn) {
    const id = delBtn.dataset.deleteServer;
    const p = state.data.profiles.find((x) => x.id === id);
    if (p) {
      state.deleteCandidate = p;
      state.modal = "confirm-delete";
      render();
    }
    return;
  }

  // Просмотр выданного ключа
  const keyBtn = e.target.closest("[data-show-key]");
  if (keyBtn) {
    const k = state.data.issued.find((x) => x.id === keyBtn.dataset.showKey);
    if (!k) return;
    state.issue.made = k;
    try {
      state.issue.qr = await invoke("qr_svg", { text: k.key });
    } catch (_) {}
    state.route = "issued";
    render();
    return;
  }

  // Копирование
  const copyBtn = e.target.closest("[data-copy-text]");
  if (copyBtn) {
    const text = copyBtn.dataset.copyText;
    if (!text) return;
    try {
      await invoke("write_clipboard", { text });
      showToast("Скопировано в буфер");
    } catch (_) {
      try {
        await navigator.clipboard.writeText(text);
        showToast("Скопировано в буфер");
      } catch (err) {
        showToast("Не удалось скопировать", "error");
      }
    }
    return;
  }

  // Копирование ссылки сервера (obsidian:// URI)
  const copyUriBtn = e.target.closest("[data-copy-server-uri]");
  if (copyUriBtn) {
    const serverId = copyUriBtn.dataset.copyServerUri;
    if (!serverId) return;
    try {
      const uri = await invoke("export_server_uri", { serverId });
      try {
        await invoke("write_clipboard", { text: uri });
      } catch (_) {
        await navigator.clipboard.writeText(uri);
      }
      showToast("Ссылка obsidian:// скопирована");
    } catch (err) {
      showToast(String(err), "error");
    }
    return;
  }

  // Переключение настроек
  const toggleBtn = e.target.closest("[data-toggle-setting]");
  if (toggleBtn) {
    const key = toggleBtn.dataset.toggleSetting;
    const nextSettings = {
      ...state.data.settings,
      [key]: !state.data.settings[key],
    };
    try {
      state.data = await invoke("save_settings", { settings: nextSettings });
      showToast("Настройка сохранена");
    } catch (err) {
      showToast(String(err), "error");
    }
    render();
    return;
  }

  // Аутентификация в деплое
  const authBtn = e.target.closest("[data-deploy-auth]");
  if (authBtn) {
    saveDeployInputs();
    state.deploy.auth = authBtn.dataset.deployAuth;
    render();
    return;
  }

  // Дни в выдаче ключа
  const daysBtn = e.target.closest("[data-issue-days]");
  if (daysBtn) {
    state.issue.days = Number(daysBtn.dataset.issueDays);
    const nameInput = document.getElementById("issue-name");
    if (nameInput) state.issue.name = nameInput.value;
    render();
    return;
  }

  // Пресеты раздельного туннелирования
  const presetBtn = e.target.closest("[data-add-preset]");
  if (presetBtn) {
    const preset = presetBtn.dataset.addPreset;
    const area = document.getElementById("split-input");
    if (!area) return;

    const presetsMap = {
      gosuslugi: ["gosuslugi.ru", "sberbank.ru", "tbank.ru", "vtb.ru", "nalog.ru", "mos.ru"],
      "ru-media": ["vk.com", "yandex.ru", "ya.ru", "kinopoisk.ru", "dzen.ru", "mail.ru", "rutube.ru"],
      "ru-all": ["*.ru", "*.рф", "*.su"],
    };

    if (preset === "clear") {
      area.value = "";
      state.splitDraft = "";
      return;
    }

    const additions = presetsMap[preset] || [];
    const current = area.value.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
    for (const item of additions) {
      if (!current.includes(item)) current.push(item);
    }
    area.value = current.join("\n");
    state.splitDraft = area.value;
    return;
  }

  // Общие действия
  const actBtn = e.target.closest("[data-act]");
  if (!actBtn) return;
  const act = actBtn.dataset.act;

  if (act === "min") return win().minimize();
  if (act === "close") return win().close();

  if (act === "back") {
    if (state.route === "issued" || state.route === "issue") state.route = "access";
    else if (state.route === "deploy") state.route = state.deploy.kind === "update" ? "access" : "servers";
    else if (state.route === "server-manage") state.route = "servers";
    else state.route = "home";
    state.modal = null;
    render();
    return;
  }

  // Подключение/отключение туннеля
  if (act === "toggle-vpn") {
    const st = state.data.vpn.status;
    if (st === "connected" || st === "connecting") {
      try {
        state.data = await invoke("disconnect");
      } catch (err) {
        showToast(String(err), "error");
      }
    } else {
      if (!selectedProfile()) {
        state.route = "servers";
        render();
        showToast("Сначала добавьте сервер");
        return;
      }
      try {
        state.data = await invoke("connect");
      } catch (err) {
        state.data.vpn = { ...state.data.vpn, status: "error", error: String(err) };
      }
    }
    render();
    return;
  }

  if (act === "open-add-key") {
    state.modal = "add-key";
    state.keyDraft = "";
    state.keyHint = null;
    render();
    setTimeout(() => document.getElementById("key-input")?.focus(), 40);
    return;
  }

  if (act === "close-modal") {
    state.modal = null;
    state.deleteCandidate = null;
    render();
    return;
  }

  if (act === "paste-key-clipboard") {
    try {
      let text = await invoke("read_clipboard");
      if (!text) text = await navigator.clipboard.readText();
      if (text) {
        const input = document.getElementById("key-input");
        if (input) {
          input.value = text.trim();
          input.dispatchEvent(new Event("input", { bubbles: true }));
        }
      }
    } catch (_) {
      showToast("Не удалось прочитать буфер", "error");
    }
    return;
  }

  if (act === "save-key-action") {
    const v = document.getElementById("key-input")?.value.trim() || state.keyDraft.trim();
    if (!v) {
      showToast("Введите или вставьте ссылку или ключ доступа", "error");
      return;
    }
    try {
      state.data = await invoke("add_key", { key: v });
      state.modal = null;
      state.route = "home";
      showToast("Сервер добавлен");
    } catch (err) {
      state.keyHint = { ok: false, text: String(err) };
      updateKeyHintDOM();
    }
    render();
    return;
  }

  if (act === "confirm-delete-action") {
    const p = state.deleteCandidate;
    if (p) {
      try {
        state.data = await invoke("remove_profile", { id: p.id });
        showToast("Сервер удален");
      } catch (err) {
        showToast(String(err), "error");
      }
    }
    state.modal = null;
    state.deleteCandidate = null;
    render();
    return;
  }

  if (act === "open-split") {
    const p = selectedProfile();
    state.modal = "split";
    state.splitDraft = (p?.config?.split_sites || []).join("\n");
    render();
    return;
  }

  if (act === "save-split-action") {
    const p = selectedProfile();
    if (p) {
      const text = document.getElementById("split-input")?.value || "";
      const sites = text.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
      try {
        state.data = await invoke("set_split_tunnel", {
          id: p.id,
          mode: "exclude",
          sites,
        });
        showToast("Настройки туннелирования сохранены");
      } catch (err) {
        showToast(String(err), "error");
      }
    }
    state.modal = null;
    render();
    return;
  }

  if (act === "open-deploy") {
    openDeployWizard("deploy");
    return;
  }

  if (act === "open-update-fw") {
    const p = ownServer();
    if (!p) {
      state.route = "servers";
      render();
      return;
    }
    openDeployWizard("update", p);
    return;
  }

  if (act === "open-manage-vps") {
    const p = ownServer();
    if (!p) {
      state.route = "servers";
    } else {
      state.managingServerId = p.id;
      state.manageSniDraft = p.config?.reality_sni || p.config?.sni || "www.microsoft.com";
      state.manageCreds = {
        auth: p.ssh_auth || (p.ssh_key_path ? "key" : "password"),
        keyPath: p.ssh_key_path || "",
        keyLabel: p.ssh_key_path ? p.ssh_key_path.split(/[/\\]/).pop() : "",
        showPassword: false,
      };
      state.route = "server-manage";
    }
    render();
    return;
  }

  if (act === "apply-manage-sni") {
    const input = document.getElementById("manage-sni-input");
    const sni = (input?.value || state.manageSniDraft || "").trim();
    if (!sni) {
      showToast("Укажите домен для SNI", "error");
      return;
    }
    const serverId = state.managingServerId || ownServer()?.id;
    if (!serverId) return;
    state.manageLoading = "sni";
    render();
    try {
      state.data = await invoke("change_server_sni", { serverId, newSni: sni });
      state.manageSniDraft = sni;
      showToast(`SNI обновлен на ${sni}`);
    } catch (err) {
      showToast(String(err), "error");
    } finally {
      state.manageLoading = null;
      render();
    }
    return;
  }

  if (act === "open-reset-confirm") {
    state.modal = "confirm-reset";
    render();
    return;
  }

  if (act === "confirm-reset-action") {
    const serverId = state.managingServerId || ownServer()?.id;
    state.modal = null;
    if (!serverId) return;
    state.manageLoading = "reset";
    state.manageProgress = { pct: 15, stage: "Подключение к SSH..." };
    invoke("set_taskbar_progress", { progress: 15, stateName: "normal" }).catch(() => {});
    render();
    try {
      state.data = await invoke("reset_server", { serverId });
      showToast("Сервер успешно обнулен");
      invoke("set_taskbar_progress", { progress: null, stateName: "none" }).catch(() => {});
    } catch (err) {
      invoke("set_taskbar_progress", { progress: 100, stateName: "error" }).catch(() => {});
      showToast(String(err), "error");
    } finally {
      state.manageLoading = null;
      state.manageProgress = null;
      render();
    }
    return;
  }

  if (act === "toggle-manage-ipv6") {
    const serverId = state.managingServerId || ownServer()?.id;
    if (!serverId) return;
    try {
      state.data = await invoke("toggle_server_ipv6", { serverId });
      const currentP = state.data.profiles.find((x) => x.id === serverId);
      const isIpv6 = Boolean(currentP?.config?.enable_ipv6);
      const isConnected = state.data.vpn?.status === "connected";
      const hint = isConnected ? " (переподключитесь для применения)" : "";
      showToast(isIpv6 ? `Включен IPv6 Dual-Stack${hint}` : `Включен чистый IPv4 (370+ Мбит/с)${hint}`);
    } catch (err) {
      showToast(String(err), "error");
    }
    render();
    return;
  }

  if (act === "update-manage-fw") {
    const serverId = state.managingServerId || ownServer()?.id;
    if (!serverId) return;
    state.manageLoading = "update";
    state.manageProgress = { pct: 10, stage: "Подключение к SSH..." };
    invoke("set_taskbar_progress", { progress: 10, stateName: "normal" }).catch(() => {});
    render();
    try {
      state.data = await invoke("update_server_firmware", { serverId });
      showToast("Ядро сервера успешно обновлено");
      invoke("set_taskbar_progress", { progress: null, stateName: "none" }).catch(() => {});
    } catch (err) {
      invoke("set_taskbar_progress", { progress: 100, stateName: "error" }).catch(() => {});
      showToast(String(err), "error");
    } finally {
      state.manageLoading = null;
      state.manageProgress = null;
      render();
    }
    return;
  }

  if (act === "check-manage-version") {
    const serverId = state.managingServerId || ownServer()?.id;
    if (!serverId) return;
    state.manageLoading = "check";
    render();
    try {
      state.data = await invoke("check_server_version", { serverId });
      const p = state.data.profiles.find((x) => x.id === serverId);
      if (p?.needs_update) {
        showToast("Доступно обновление ядра сервера");
      } else {
        showToast("Версия ядра сервера актуальна");
      }
    } catch (err) {
      showToast(String(err), "error");
    } finally {
      state.manageLoading = null;
      render();
    }
    return;
  }

  if (act === "toggle-manage-password") {
    if (!state.manageCreds) state.manageCreds = {};
    state.manageCreds.showPassword = !state.manageCreds.showPassword;
    render();
    return;
  }

  if (act === "pick-manage-ssh-key") {
    try {
      const path = await invoke("pick_ssh_key");
      if (path) {
        if (!state.manageCreds) state.manageCreds = {};
        state.manageCreds.keyPath = path;
        state.manageCreds.keyLabel = path.split(/[/\\]/).pop();
        render();
      }
    } catch (err) {
      showToast(String(err), "error");
    }
    return;
  }

  if (act === "save-manage-credentials") {
    const serverId = state.managingServerId || ownServer()?.id;
    if (!serverId) return;
    const host = (document.getElementById("manage-cred-host")?.value || "").trim();
    const portStr = (document.getElementById("manage-cred-port")?.value || "22").trim();
    const port = parseInt(portStr, 10) || 22;
    const user = (document.getElementById("manage-cred-user")?.value || "root").trim();
    const auth = state.manageCreds?.auth || "password";
    const password = document.getElementById("manage-cred-pass")?.value || "";
    const rawKey = (document.getElementById("manage-cred-rawkey")?.value || "").trim();
    const keyPath = state.manageCreds?.keyPath || "";

    state.manageLoading = "save-cred";
    render();
    try {
      state.data = await invoke("save_server_credentials", {
        serverId,
        host,
        port,
        user,
        auth,
        password: password ? password : null,
        keyPath: keyPath ? keyPath : null,
        rawKey: rawKey ? rawKey : null,
      });
      if (!state.manageCreds) state.manageCreds = {};
      state.manageCreds.showPassword = false;
      showToast("Реквизиты SSH сохранены");
    } catch (err) {
      showToast(String(err), "error");
    } finally {
      state.manageLoading = null;
      render();
    }
    return;
  }

  if (act === "pick-deploy-ssh-key") {
    saveDeployInputs();
    try {
      const path = await invoke("pick_ssh_key");
      if (path) {
        state.deploy.keyPath = path;
        const base = path.split(/[/\\]/).pop();
        state.deploy.keyLabel = `Ключ: ${base}`;
      }
    } catch (_) {}
    render();
    return;
  }

  if (act === "start-deploy-run") {
    saveDeployInputs();
    if (!state.deploy.host.trim()) {
      showToast("Укажите IP-адрес сервера", "error");
      return;
    }
    state.deploy.step = 2;
    state.deploy.log = "Подключение к серверу...\n";
    state.deploy.progress = 5;
    render();

    const req = {
      host: state.deploy.host.trim(),
      user: state.deploy.user.trim() || "root",
      port: Number(state.deploy.port || 22),
      auth: state.deploy.auth,
      password: state.deploy.password || null,
      keyPath: state.deploy.keyPath || null,
      mask: state.deploy.mask || "www.microsoft.com",
    };

    try {
      if (state.deploy.kind === "update") {
        state.data = await invoke("start_update", { req });
        state.deploy.step = 3;
        state.deploy.progress = 100;
        showToast("Обновление завершено");
      } else {
        const nextState = await invoke("start_deploy", { req });
        state.data = nextState;
        const ownerKey = state.data.issued[0];
        state.deploy.result = {
          share: ownerKey?.key,
          keyserver_url: selectedProfile()?.keyserver_url,
          admin_token: selectedProfile()?.keyserver_admin_token,
        };
        state.deploy.step = 3;
        state.deploy.progress = 100;
        showToast("Сервер успешно развернут");
      }
    } catch (err) {
      state.deploy.log += `\n[Ошибка]: ${err}`;
      state.deploy.step = 1;
      showToast(String(err), "error");
    }
    render();
    return;
  }

  if (act === "deploy-finish") {
    state.route = state.deploy.kind === "update" ? "access" : "home";
    render();
    return;
  }

  if (act === "open-issue-form") {
    state.route = "issue";
    render();
    return;
  }

  if (act === "dev-minus") {
    state.issue.devices = Math.max(1, state.issue.devices - 1);
    const nameInput = document.getElementById("issue-name");
    if (nameInput) state.issue.name = nameInput.value;
    render();
    return;
  }

  if (act === "dev-plus") {
    state.issue.devices = Math.min(20, state.issue.devices + 1);
    const nameInput = document.getElementById("issue-name");
    if (nameInput) state.issue.name = nameInput.value;
    render();
    return;
  }

  if (act === "submit-issue-key") {
    const name = document.getElementById("issue-name")?.value.trim() || state.issue.name;
    try {
      const made = await invoke("issue_key", {
        name,
        days: state.issue.days,
        devices: state.issue.devices,
      });
      state.issue.made = made;
      state.issue.qr = await invoke("qr_svg", { text: made.key });
      state.data = await invoke("load_state");
      state.route = "issued";
      showToast("Ключ доступа создан");
    } catch (err) {
      showToast(String(err), "error");
    }
    render();
  }
});

// Запрос и обновление пингов
async function refreshPings() {
  let changed = false;
  for (const p of state.data.profiles) {
    const host = p.config?.server_host;
    const port = p.config?.server_port || "443";
    if (!host) continue;
    try {
      const ms = await invoke("ping_host", { host, port: String(port) });
      if (ms != null && state.pings[p.id] !== ms) {
        state.pings[p.id] = ms;
        changed = true;
      }
    } catch (_) {}
  }
  if (changed && (state.route === "home" || state.route === "servers")) {
    render();
  }
}

function patchConnectingDOM(vpn) {
  const stageEl = document.querySelector(".connecting-taskbar .process-taskbar-stage");
  const pctEl = document.querySelector(".connecting-taskbar .process-taskbar-pct");
  const fillEl = document.querySelector(".connecting-taskbar .process-taskbar-fill");
  const noteEl = document.querySelector(".dial-metrics .connection-sub-note");

  const stage = vpn.stage || "Подготовка соединения...";
  const pct = Math.max(0, Math.min(100, Math.round(vpn.progress || 0)));

  if (stageEl) stageEl.textContent = stage;
  if (pctEl) pctEl.textContent = `${pct}%`;
  if (fillEl) fillEl.style.width = `${Math.max(4, pct)}%`;
  if (noteEl) noteEl.textContent = vpn.detail || "Запуск сетевого интерфейса...";
}

let lastVpnStatus = "disconnected";

// Запуск клиента
async function boot() {
  try {
    state.data = await invoke("load_state");
    lastVpnStatus = state.data?.vpn?.status || "disconnected";
  } catch (err) {
    console.error("load_state error:", err);
  }

  await listen("vpn-status", (ev) => {
    const prevStatus = lastVpnStatus;
    const newVpn = ev.payload;
    state.data.vpn = newVpn;
    lastVpnStatus = newVpn.status;

    // Синхронизация с таскбаром Windows (иконка в панели задач)
    if (newVpn.status === "connecting") {
      const pct = Math.max(0, Math.min(100, Math.round(newVpn.progress || 0)));
      invoke("set_taskbar_progress", { progress: pct, stateName: "normal" }).catch(() => {});
    } else if (newVpn.status === "connected") {
      invoke("set_taskbar_progress", { progress: null, stateName: "none" }).catch(() => {});
    } else if (newVpn.status === "error") {
      invoke("set_taskbar_progress", { progress: 100, stateName: "error" }).catch(() => {});
    } else {
      invoke("set_taskbar_progress", { progress: null, stateName: "none" }).catch(() => {});
    }

    // Бесшовное обновление DOM без пересоздания SVG-диска при подключении
    if (state.route === "home" && prevStatus === "connecting" && newVpn.status === "connecting") {
      patchConnectingDOM(newVpn);
      return;
    }

    render();
  });

  await listen("auto-connect", async () => {
    if (!selectedProfile()) return;
    try {
      state.data = await invoke("connect");
    } catch (err) {
      state.data.vpn = { ...state.data.vpn, status: "error", error: String(err) };
    }
    render();
  });

  await listen("deploy-log", (ev) => {
    state.deploy.log += (state.deploy.log ? "\n" : "") + ev.payload;
    const terminal = document.getElementById("deploy-terminal");
    if (terminal) {
      terminal.textContent = state.deploy.log;
      terminal.scrollTop = terminal.scrollHeight;
    }
  });

  await listen("deploy-progress", (ev) => {
    state.deploy.progress = ev.payload;
    const pct = ev.payload;

    // Обновляем шкалы деплоя
    const deployFills = document.querySelectorAll(".deploy-taskbar-fill, .linear-progress-fill");
    deployFills.forEach((f) => { f.style.width = `${Math.max(4, pct)}%`; });
    const deployPct = document.querySelector(".deploy-taskbar-pct");
    if (deployPct) deployPct.textContent = `${pct}%`;

    // Обновляем шкалы управления сервером (обновление / сброс)
    if (state.manageLoading && state.manageProgress) {
      state.manageProgress.pct = pct;
      const stageMap = {
        16: "Проверка окружения хоста...",
        20: "Подключение к SSH хосту...",
        35: "Загрузка нового бинарного ядра...",
        45: "Генерация новых мастер-ключей шифрования...",
        62: "Установка контроллера ключей...",
        75: "Перезапуск сетевых контейнеров...",
        78: "Проверка системных зависимостей...",
        100: "Завершено успешно"
      };
      if (stageMap[pct]) {
        state.manageProgress.stage = stageMap[pct];
      }
      const manageFill = document.querySelector(".manage-taskbar .process-taskbar-fill");
      const managePctVal = document.querySelector(".manage-taskbar .process-taskbar-pct");
      const manageStage = document.querySelector(".manage-taskbar .process-taskbar-stage");
      if (manageFill) manageFill.style.width = `${Math.max(4, pct)}%`;
      if (managePctVal) managePctVal.textContent = `${pct}%`;
      if (manageStage && state.manageProgress.stage) manageStage.textContent = state.manageProgress.stage;
    }

    invoke("set_taskbar_progress", { progress: pct, stateName: "normal" }).catch(() => {});
  });

  await listen("deploy-result", (ev) => {
    state.deploy.result = {
      ...state.deploy.result,
      ...ev.payload,
      share: state.deploy.result?.share,
    };
    if (ev.payload && ev.payload.status === "error") {
      invoke("set_taskbar_progress", { progress: 100, stateName: "error" }).catch(() => {});
    } else {
      invoke("set_taskbar_progress", { progress: null, stateName: "none" }).catch(() => {});
    }
  });

  render();
  if (initialParams?.get("scroll") === "bottom") {
    const sc = document.querySelector(".page-scroll");
    if (sc) sc.scrollTop = sc.scrollHeight;
  }
  refreshPings();

  setInterval(refreshPings, 30000);

  setInterval(() => {
    if (state.data.vpn.status === "connected") {
      const clock = document.querySelector(".session-clock");
      if (clock) {
        clock.textContent = elapsed(state.data.vpn.connected_at);
      }
    }
  }, 1000);
}

boot();

// Хук для визуального тестирования и отладки скриншотов
window.__setStateRoute = (route, modal, managingServerId = null, extra = null) => {
  if (route) state.route = route;
  state.modal = modal || null;
  if (managingServerId) {
    state.managingServerId = managingServerId;
  } else if (route === "server-manage" && !state.managingServerId) {
    const own = ownServer();
    if (own) state.managingServerId = own.id;
  }
  if (extra) {
    if (extra.vpn) Object.assign(state.data.vpn, extra.vpn);
    if (extra.manageLoading) state.manageLoading = extra.manageLoading;
    if (extra.manageProgress) state.manageProgress = extra.manageProgress;
    if (extra.deploy) Object.assign(state.deploy, extra.deploy);
  }
  render();
};
