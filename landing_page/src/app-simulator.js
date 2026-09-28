import css from "./app-simulator.css?inline";
import "./experience.css";
import { CityMap, places, project, unproject, along } from "./simulator-map.js";
import {
  outageDurations,
  faultPresets,
  signalState,
  outageResult,
} from "./simulator-scenarios.js";

const paths = {
  home: "M3 10 12 3l9 7M5 9v12h5v-7h4v7h5V9",
  map: "m3 5 6-2 6 2 6-2v16l-6 2-6-2-6 2ZM9 3v16M15 5v16",
  sensors:
    "M4 5a10 10 0 0 0 0 14M7 8a6 6 0 0 0 0 8M17 8a6 6 0 0 1 0 8M20 5a10 10 0 0 1 0 14M12 10v4",
  profile: "M12 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8M4 21v-2a8 6 0 0 1 16 0v2Z",
  locate:
    "M12 1v4M12 19v4M1 12h4M19 12h4M12 5a7 7 0 1 0 0 14 7 7 0 0 0 0-14M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6",
  pin: "M12 22s8-9 8-14a8 8 0 1 0-16 0c0 5 8 14 8 14ZM12 5a3 3 0 1 0 0 6 3 3 0 0 0 0-6",
  arrow: "m12 2 8 19-8-4-8 4Z",
  back: "m15 5-7 7 7 7",
  close: "m6 6 12 12M6 18 18 6",
  expand: "M8 3H3v5M16 3h5v5M3 16v5h5M21 16v5h-5",
  plus: "M5 12h14M12 5v14",
  minus: "M5 12h14",
  turn: "M17 21V9H5m5-5L5 9l5 5",
  swap: "M7 3v18m-4-4 4 4 4-4M17 21V3m-4 4 4-4 4 4",
  flask: "M9 3h6M10 3v7L4 20h16l-6-10V3",
  play: "m8 4 12 8-12 8Z",
  pause: "M8 4v16M16 4v16",
  check: "m5 12 4 4 10-10",
  car: "m4 9 2-6h12l2 6M3 9h18v9H3ZM5 18v3M19 18v3M6 13h2M16 13h2",
  walk: "M13 2v2M9 8l4-2 3 5 4 1M12 7l-2 8-4 6M11 13l5 3 2 5M9 8l-4 4",
  bike: "M5 12a4 4 0 1 0 0 8 4 4 0 0 0 0-8M19 12a4 4 0 1 0 0 8 4 4 0 0 0 0-8M5 16l6-9 8 9M8 6h5M11 7l-1 9h9M15 4h3l1 3",
  moon: "M21 13A9 9 0 0 1 11 3a9 9 0 1 0 10 10Z",
  phone: "M6 2h12v20H6ZM10 18h4",
  info: "M12 10v7M12 6v1M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20",
  chevron: "m9 5 7 7-7 7",
  download: "M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5",
  wifi: "M2 7a16 16 0 0 1 20 0M6 11a9 9 0 0 1 12 0M10 15a3 3 0 0 1 4 0M12 19v1",
  battery: "M3 7h17v12H3ZM20 11h2v4M6 10h10v6H6Z",
  compass: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20m4 6-3 5-5 3 3-5Z",
};
const icon = (name) =>
  `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name] || paths.info}"/></svg>`;
const esc = (text) =>
  String(text).replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const actionLabels = {
  back: "Back",
  swap: "Swap starting point and destination",
  expand: "Expand app",
  north: "Reset north",
  "zoom-in": "Zoom in",
  "zoom-out": "Zoom out",
  center: "Recenter map",
};
const button = (action, label, cls = "", glyph = "") =>
  `<button type="button" data-action="${action}" class="${cls}" ${actionLabels[action] ? `aria-label="${actionLabels[action]}"` : ""}>${glyph ? icon(glyph) : ""}${label}</button>`;
const BASE = import.meta.env.BASE_URL;
let cityPromise;
function loadCity() {
  if (!cityPromise)
    cityPromise = fetch(`${BASE}simulator/mumbai.json`)
      .then((r) => {
        if (!r.ok) throw new Error("Map unavailable");
        return r.json();
      })
      .then((data) => new CityMap(data))
      .catch((error) => {
        cityPromise = null;
        throw error;
      });
  return cityPromise;
}

class GatiSimulator extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this.state = {
      tab: "map",
      page: null,
      from: places[0],
      to: places[1],
      route: null,
      active: true,
      running: false,
      progress: 0,
      signal: "locked",
      scenario: null,
      scenarioTime: 0,
      duration: 30,
      outageLog: [],
      lastOutage: null,
      fault: 0,
      toolJob: null,
      toolResult: null,
      diagnosticsPaused: false,
      events: ["Navigation ready · Mumbai map loaded"],
      recording: false,
      recordSeconds: 0,
      records: [],
      vehicle: "Car",
      dark: true,
      automatic: false,
      haptics: true,
      voice: true,
      maps: true,
      zoom: 3,
      following: true,
      pan: [0, 0],
      sheet: null,
      prepared: false,
    };
    this.visible = true;
    this.lastTick = 0;
    this.targetField = "to";
    this.pointers = new Map();
    this.mapMode = "route";
    try {
      const settings = JSON.parse(
        localStorage.getItem("gatisaarth-web-preferences") || "{}",
      );
      for (const key of ["dark", "automatic", "haptics", "voice"])
        if (typeof settings[key] === "boolean") this.state[key] = settings[key];
      if (["Car", "Walk", "Two-wheeler"].includes(settings.vehicle))
        this.state.vehicle = settings.vehicle;
    } catch {
      /* Storage is optional in private or restricted browsing. */
    }
  }
  connectedCallback() {
    if (this.initialized) return;
    this.initialized = true;
    this.shadowRoot.innerHTML = `<style>${css}</style><div class="shell"><div class="map-loading">Opening GatiSaarth…</div></div>`;
    this.resize = new ResizeObserver(() => this.fit());
    this.resize.observe(this);
    this.fit();
    this.visibility = new IntersectionObserver((entries) => {
      this.visible = entries[0].isIntersecting;
      this.lastTick = 0;
    });
    this.visibility.observe(this);
    this.shadowRoot.addEventListener("click", (e) => this.click(e));
    this.shadowRoot.addEventListener("input", (e) => this.input(e));
    this.shadowRoot.addEventListener("change", (e) => {
      if (e.target.name === "sample-source")
        this.state.sampleSource = e.target.value;
    });
    this.shadowRoot.addEventListener("focusin", (e) => {
      if (e.target.name === "from" || e.target.name === "to")
        this.targetField = e.target.name;
    });
    this.shadowRoot.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && (this.state.sheet || this.state.page)) {
        e.preventDefault();
        e.stopPropagation();
        this.back();
      }
      if (e.key === "Enter" && e.target.matches("input")) {
        e.preventDefault();
        this.shadowRoot.querySelector(".result")?.click();
      }
      if (
        e.target.matches(".map-area") &&
        ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "+", "-"].includes(
          e.key,
        )
      ) {
        e.preventDefault();
        const deltas = {
          ArrowUp: [0, 30],
          ArrowDown: [0, -30],
          ArrowLeft: [30, 0],
          ArrowRight: [-30, 0],
        };
        if (deltas[e.key]) {
          this.state.pan = this.state.pan.map((n, i) => n + deltas[e.key][i]);
          this.updateMap();
        } else this.zoom(e.key === "+" ? 1.25 : 0.8);
      }
    });
    this.shadowRoot.addEventListener("pointerdown", (e) => this.pointerDown(e));
    this.shadowRoot.addEventListener("pointermove", (e) => this.pointerMove(e));
    this.shadowRoot.addEventListener("pointerup", (e) => this.pointerUp(e));
    this.shadowRoot.addEventListener("pointercancel", () => {
      this.drag = null;
      this.pinch = null;
      this.pointers.clear();
    });
    this.shadowRoot.addEventListener(
      "wheel",
      (e) => {
        if (e.target.closest(".map-area") && (this.expanded || e.ctrlKey)) {
          e.preventDefault();
          this.zoom(e.deltaY < 0 ? 1.12 : 0.89);
        }
      },
      { passive: false },
    );
    this.timer = setInterval(() => this.tick(), 50);
    this.initialize();
  }
  disconnectedCallback() {
    // Moving the single instance into a dialog briefly disconnects it.
    queueMicrotask(() => {
      if (!this.isConnected) {
        clearInterval(this.timer);
        clearTimeout(this.planTimer);
        clearTimeout(this.toastTimer);
        this.resize?.disconnect();
        this.visibility?.disconnect();
      }
    });
  }
  async initialize() {
    try {
      this.city = await loadCity();
      this.state.route = this.city.route(this.state.from, this.state.to);
      this.state.prepared = true;
      this.render();
    } catch {
      this.shadowRoot.querySelector(".shell").innerHTML =
        `<div class="scroller"><h1 class="page-title">Open GatiSaarth</h1><p>The local map couldn’t load.</p>${button("retry", "Try again", "primary")}</div>`;
    }
  }
  set expanded(value) {
    this._expanded = value;
    this.toggleAttribute("expanded", value);
    this.fit();
  }
  get expanded() {
    return !!this._expanded;
  }
  fit() {
    const width = this.clientWidth;
    if (!width) return;
    const compact =
      this.expanded && width > this.clientHeight && this.clientHeight < 520;
    const logicalWidth = compact ? Math.max(600, width) : 390;
    this.shadowRoot
      .querySelector(".shell")
      ?.classList.toggle("compact", compact);
    this.shadowRoot
      .querySelector(".shell")
      ?.classList.toggle(
        "short",
        !compact && this.clientHeight / (width / 390) < 650,
      );
    this.style.setProperty("--shell-width", `${logicalWidth}px`);
    this.scale = width / logicalWidth;
    this.style.setProperty("--app-scale", this.scale);
    this.style.setProperty(
      "--shell-height",
      `${this.clientHeight / this.scale}px`,
    );
    this.updateMap();
  }
  save() {
    try {
      localStorage.setItem(
        "gatisaarth-web-preferences",
        JSON.stringify(
          Object.fromEntries(
            ["dark", "automatic", "haptics", "voice", "vehicle"].map((k) => [
              k,
              this.state[k],
            ]),
          ),
        ),
      );
    } catch {}
  }
  render() {
    if (!this.city) return;
    const s = this.state,
      page = s.page;
    this.shadowRoot.querySelector(".shell").classList.toggle("light", !s.dark);
    this.shadowRoot.querySelector(".shell").innerHTML =
      `<div class="statusbar"><span>9:41</span><span>${icon("pin")}${icon("wifi")}${icon("battery")}</span></div>
      <main class="screen view-in" aria-label="${page || s.tab} screen">${page ? this.page() : this[s.tab]()}</main>
      ${page ? "" : `<nav class="nav" aria-label="App navigation">${["home", "map", "sensors", "profile"].map((tab) => `<button type="button" data-tab="${tab}" aria-current="${s.tab === tab ? "page" : "false"}">${icon(tab)}${tab[0].toUpperCase() + tab.slice(1)}</button>`).join("")}</nav>`}
      <div class="home-indicator" aria-hidden="true"></div><div class="sheet-host"></div><div class="toast" role="status" hidden></div>`;
    this.updateMap();
    this.renderSheet();
    this.updateHUD();
  }
  home() {
    const s = this.state;
    return `<div class="scroller"><h1 class="page-title">Home</h1>
    <div class="card"><div class="row"><span class="badge-icon">${icon("locate")}</span><div><h2>${s.signal === "locked" ? "Location is ready" : "Motion carries your position"}</h2><p>${s.signal === "locked" ? "GPS connected · ±5 m" : "Dead reckoning active"}</p></div></div><div class="stats"><div><small>LOCATION</small><strong>${s.signal === "locked" ? "Connected" : "Estimated"}</strong></div><div><small>SENSORS</small><strong>Active</strong></div></div></div>
    <h2 class="section-title">At a glance</h2><div class="card"><div class="stats single"><div><small>SPEED</small><strong class="blue" data-speed>0</strong> <small style="display:inline">km/h</small></div><div><small>ACCURACY</small><strong data-accuracy>±5 m</strong></div><div><small>PHONE</small><strong>${s.progress > 0.1 ? "Aligned" : "Needs drive"}</strong></div></div></div>
    ${
      s.active
        ? `<div class="card"><h2 class="row"><span class="blue">${icon("arrow")}</span>${esc(s.to.name)}</h2><p data-remaining></p><div class="actions">${button("resume", "Resume navigation", "primary", "arrow")}${button("end", "End", "text-button")}</div>${button("plan", "Plan another journey", "text-button wide")}</div>`
        : `<button class="card route-card" data-action="plan"><div class="row"><span class="blue">${icon("locate")}</span><div><small>From</small><strong>Your location</strong></div></div><div class="row"><span class="blue">${icon("pin")}</span><div><small>To</small><strong>Choose destination</strong></div>${icon("chevron")}</div></button>`
    }
    ${button("health", "System health", "outline", "sensors")}${s.records.length ? `<h2 class="section-title">Recent drives</h2>${button("records", `${s.records.length} saved drive${s.records.length > 1 ? "s" : ""} · View recordings`, "outline")}` : ""}</div>`;
  }
  mapMarkup(preview = false) {
    return `<div class="map-area" tabindex="0" role="application" aria-label="Mumbai map. Drag to pan, use plus and minus to zoom. ${this.state.page === "pick" ? "Tap to choose a point." : ""}">
    <svg class="city-svg" aria-label="Mumbai streets and navigation route" role="img"><g aria-hidden="true">${this.city.svg}</g><path class="route-line"/><path class="route-trail"/><circle class="destination-dot" r="5"/><path class="heading-cone" d="M0 0 -14 -38 Q0 -44 14 -38Z"/><circle class="position-ring" r="14"/><circle class="position-dot" r="5"/></svg>
    <div class="map-ui">${
      preview
        ? ""
        : `<div class="gnss-chip"><span class="dot" data-signal-dot></span><span data-signal>GNSS locked</span></div>
      ${this.state.active ? `<div class="turn-banner"><span class="badge-icon">${icon("turn")}</span><div><strong data-turn-distance>730 m</strong><small data-turn>Keep left onto Dr Dadabhai Naoroji Road</small></div></div>` : ""}
      <div class="integrity" data-integrity>● Position reliable · GNSS accuracy ±5 m</div>`
    }
      <div class="map-tools">${button("north", icon("compass"), "", "")}${button("expand", icon("expand"))}${button("zoom-in", icon("plus"))}${button("zoom-out", icon("minus"))}${button("center", icon("locate"))}</div>
      <a class="map-credit" href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">© OpenStreetMap contributors · Protomaps</a>
      <div class="map-coordinates"><span data-coordinate>18.9401°N, 72.8347°E</span><strong class="green" data-accuracy>±5 m</strong></div>
    </div></div>`;
  }
  map() {
    const s = this.state;
    return `${this.mapMarkup()}<div class="map-panel">
    ${button("lab", `${icon("flask")}<span data-lab-label>Simulation Lab</span>`, "lab-button")}
    <div class="journey-bar"><span data-remaining></span>${s.active ? `${button("drive", `${icon(s.running ? "pause" : "play")}<span data-drive-label>${s.running ? "Pause" : "Start drive"}</span>`, "play-drive")}${button("end", "End route")}` : button("plan", "Plan a journey", "text-button")}</div>
    <div class="metrics"><div class="metric"><small>SPEED</small><strong data-speed>0</strong><em>km/h</em></div><div class="metric accuracy"><small>LOCATION</small><strong data-accuracy>±5 m</strong><p data-mode>GPS accuracy</p></div></div>
    ${button("record", `<span class="dot"></span><span data-record>${s.recording ? "Stop recording" : "Record drive"}</span>`, "record-button")}</div>`;
  }
  sensors() {
    const s = this.state;
    return `<div class="scroller"><h1 class="page-title">System health</h1><p class="subtitle">A quick read on your navigation setup</p>
    <div class="card row"><span class="badge-icon" style="background:#ff9f0a20;color:var(--amber)">${icon("info")}</span><div><h2>${s.progress > 0.1 ? "Ready for the road" : "Setup in progress"}</h2><p>${s.progress > 0.1 ? "Your navigation signals are connected" : "Some navigation signals need attention"}</p></div></div>
    <div class="list-card"><div class="list-row">${icon("pin")}<div><h3>Location</h3><p data-health-location>GPS signal · ±5 m</p></div><strong class="green" data-health-status>Connected</strong></div>
    <div class="list-row">${icon("sensors")}<div><h3>Motion sensors</h3><p>Accelerometer, gyroscope and compass</p></div><strong>Active</strong></div>
    <div class="list-row">${icon("phone")}<div><h3>Phone alignment</h3><p>${s.progress > 0.1 ? "Aligned with direction of travel." : "Standing still will not align the phone. About 20 straight speed changes are needed (often 40 s or more)."}</p></div><strong class="amber">${s.progress > 0.1 ? "Aligned" : "Needs drive"}</strong></div></div>
    <details class="diagnostics"><summary>Technical diagnostics <span>✓ 5/5 live</span></summary><div class="diagnostic-grid">${["Accelerometer", "Gyroscope", "Compass", "GNSS", "Barometer", "Fusion engine"].map((title, i) => `<div>${title}<strong data-sensor="${i}">${["0.02 m/s²", "0.001 rad/s", "192°", "±5 m", "1013 hPa", "Healthy"][i]}</strong><svg class="trace" viewBox="0 0 100 30"><path d="M0 16 8 16 13 8 19 23 26 16 36 14 43 19 49 5 55 25 63 16 76 13 85 18 100 16"/></svg></div>`).join("")}</div></details></div>`;
  }
  preference(action, title, description, glyph, enabled) {
    return `<button type="button" class="list-row" data-action="${action}" role="switch" aria-checked="${enabled}"><span class="blue">${icon(glyph)}</span><div><h3>${title}</h3><p>${description}</p></div><span class="switch ${enabled ? "on" : ""}" aria-hidden="true"></span></button>`;
  }
  profile() {
    const s = this.state;
    return `<div class="scroller"><h1 class="profile-title">Vehicle Configuration</h1><p class="profile-sub">Active dynamics and filter tuning</p>
    <div class="segmented" aria-label="Vehicle profile">${["Car", "Walk", "Two-wheeler"].map((v, i) => `<button data-vehicle="${v}" aria-pressed="${s.vehicle === v}">${icon(["car", "walk", "bike"][i])}${v}</button>`).join("")}</div>
    <div class="card row"><span class="blue">${icon(s.vehicle === "Car" ? "car" : s.vehicle === "Walk" ? "walk" : "bike")}</span><div><h2 style="font-size:14px">${s.vehicle === "Car" ? "Car / Four-Wheeler" : s.vehicle === "Walk" ? "Pedestrian / Last-mile" : "Two-Wheeler"} Dynamics Active</h2><p style="font-size:12px">${s.vehicle === "Car" ? "Non-holonomic constraint (NHC) zero-lateral slip active" : s.vehicle === "Walk" ? "Vehicle-only lateral constraints disabled" : "Lean-angle compensation & bump suppression enabled"}</p></div></div>
    <h2 class="section-title">Preferences</h2><p class="profile-sub">Display, offline data, and telemetry</p><div class="list-card">
    ${this.preference("dark", "Appearance", s.dark ? "Dark mode enabled" : "Light mode enabled", "moon", s.dark)}
    ${this.preference("automatic", "Automatic activity mode", s.automatic ? "Detected · driving" : "Off · manual profile takes precedence", "walk", s.automatic)}
    ${this.preference("haptics", "Haptic alerts", "Safety patterns for GNSS loss and unsafe ambiguity", "phone", s.haptics)}
    ${this.preference("voice", "Safe outage voice", "Speaks on GNSS loss, ambiguity, and recovery", "sensors", s.voice)}
    ${[
      [
        "portal",
        "Trusted Portal Scanner",
        "Offline sample anchor pack",
        "locate",
      ],
      [
        "maps",
        "Offline Maps",
        s.maps
          ? "Mumbai · Available on this device"
          : "Mumbai · Ready to prepare",
        "map",
      ],
      [
        "outages",
        "Outage Log",
        `${s.outageLog.length} scored this session`,
        "info",
      ],
      [
        "benchmark",
        "Outage Benchmark",
        "Score a sample drive with GNSS switched off",
        "compass",
      ],
      [
        "faults",
        "Fault Injection Lab",
        "Developer · replay with injected faults",
        "flask",
      ],
      [
        "console",
        "Diagnostics Console",
        "Internal telemetry and replay logs",
        "sensors",
      ],
      [
        "records",
        "Drive recordings",
        `${s.records.length} saved locally`,
        "download",
      ],
      [
        "engine",
        "GatiSaarth Navigation Engine",
        "v5.2 · Offline ready · Specifications",
        "compass",
      ],
      [
        "about",
        "Privacy & Architecture",
        "Navigation beyond satellite coverage",
        "info",
      ],
    ]
      .map(
        ([key, title, detail, glyph]) =>
          `<button class="list-row" data-action="${key}"><span class="blue">${icon(glyph)}</span><div><h3>${title}</h3><p>${detail}</p></div>${icon("chevron")}</button>`,
      )
      .join("")}</div></div>`;
  }
  appbar(title) {
    return `<header class="appbar">${button("back", icon("back"))}<h1>${title}</h1>${button("expand", icon("expand"))}</header>`;
  }
  page() {
    const s = this.state;
    if (
      [
        "portal",
        "outages",
        "benchmark",
        "faults",
        "console",
        "engine",
      ].includes(s.page)
    )
      return this.toolPage();
    if (s.page === "plan")
      return `${this.appbar("Plan a journey")}<div class="fields"><div><label class="field">${icon("locate")}<input name="from" aria-label="Starting point" value="${esc(s.from?.name || "")}" placeholder="Your location" autocomplete="off"/></label><label class="field">${icon("pin")}<input name="to" aria-label="Destination" value="${esc(s.to?.name || "")}" placeholder="Choose destination" autocomplete="off"/></label></div>${button("swap", icon("swap"))}</div><div class="quick">${button("location", "Your location", "", "locate")}${button("pick", "Choose on map", "", "map")}</div><div class="results"><p class="muted" style="font-size:11px">Places in Mumbai, Maharashtra</p>${this.results("")}</div>`;
    if (s.page === "pick")
      return `${this.appbar("Choose on map")}${this.mapMarkup(true)}<div class="planner-bottom"><h2>Choose your destination</h2><p>Tap a street on the map to place a pin.</p>${button("use-point", "Use this location", "primary wide", "pin")}</div>`;
    if (s.page === "preview")
      return `${this.appbar("Your journey")}${this.mapMarkup(true)}<div class="planner-bottom"><h2>${esc(s.to.name)}</h2><p>${s.route.km.toFixed(1)} km · ${Math.max(3, Math.round(s.route.km * 3))} min · Via central Mumbai</p><p class="green">✓ Route maps ready · Works offline</p>${button("start", "Start navigation", "primary wide", "arrow")}${button("plan", "Change destination", "text-button wide")}</div>`;
    if (s.page === "preparing")
      return `${this.appbar("Preparing your journey")}<div class="scroller"><h1 class="page-title">Getting your route ready.</h1><div class="card"><h2>${esc(s.to.name)}</h2><p>Checking the locally stored Mumbai street map.</p><div class="progress"><span style="width:65%"></span></div><p>✓ Road coverage available</p><p>✓ Saving your journey</p></div></div>`;
    if (s.page === "maps")
      return `${this.appbar("Offline Maps")}<div class="scroller"><h1 class="page-title">Your maps. With you.</h1><p class="subtitle">Prepare before you leave the network.</p><div class="card"><h2>Mumbai, Maharashtra</h2><p>Fort · Colaba · Churchgate · Marine Drive</p><p>${s.maps ? "✓ Available offline" : "Map coverage not selected"}</p><div class="actions">${button("toggle-map", s.maps ? "Remove local selection" : "Prepare Mumbai", "primary", "map")}</div></div><p class="muted" style="font-size:12px">This web experience includes central Mumbai map data. Map preparation here uses the bundled local sample.</p></div>`;
    if (s.page === "records")
      return `${this.appbar("Drive recordings")}<div class="scroller"><h1 class="page-title">Your drives</h1>${s.records.length ? s.records.map((r, i) => `<div class="record-item"><strong>${esc(r.to)}</strong><small>${r.seconds} seconds · ${r.km.toFixed(2)} km · ${r.outages} signal gap${r.outages === 1 ? "" : "s"}</small>${button(`export-${i}`, "Export recording", "text-button", "download")}</div>`).join("") : `<div class="card"><h2>No recordings yet</h2><p>Open the map and select Record drive to save a local sample journey.</p>${button("resume", "Open map", "text-button")}</div>`}</div>`;
    return `${this.appbar("About GatiSaarth")}<div class="scroller"><h1 class="page-title">GatiSaarth</h1><div class="card"><h2>A way forward. Even off-grid.</h2><p>Developed by Team CodeAstra · Team Leader: <a href="https://www.vinitgirdhar.xyz" target="_blank" rel="noopener noreferrer" style="color:inherit;text-decoration:underline">Vinit Girdhar</a> · Team ID 120431</p><p>Interactive website experience based on the Android application. Locations, sensor readings, and journeys are simulated locally. No live GPS, hardware sensors, or navigation backend are connected.</p></div><div class="card"><h2>Visible confidence</h2><p>Motion carries a position estimate through signal gaps. Uncertainty grows until satellite fixes return. This experience illustrates that behavior; it does not measure positioning accuracy.</p></div></div>`;
  }
  reportCard(r) {
    return `<div class="card sample-report"><h2>GNSS outage · ${r.seconds} s</h2><p>Illustrative result · not a measured drive</p><dl class="report-grid">${[
      ["Travelled", `${r.distanceM} m`],
      ["DR error", `${r.errorM} m`],
      ["Along-track", `${r.alongTrackM} m`],
      ["Cross-track", `${r.crossTrackM} m`],
      ["Uncertainty", `${r.initialSigmaM} → ${r.peakSigmaM} m`],
      ["Recovery jump", `${r.recoveryJumpM} m`],
    ]
      .map(([label, value]) => `<div><dt>${label}</dt><dd>${value}</dd></div>`)
      .join("")}</dl></div>`;
  }
  toolPage() {
    const s = this.state;
    const titles = {
      portal: "Trusted portal anchor",
      outages: "Outage Log",
      benchmark: "Outage benchmark",
      faults: "Fault Injection Lab",
      console: "Diagnostics",
      engine: "Navigation Engine",
    };
    const sample = `<p class="sample-note">Local sample data · no engine or hardware measurement</p>`;
    const source = `<label class="tool-field">Choose a drive<select name="sample-source"><option value="reference">Mumbai reference drive</option>${s.records.map((r, i) => `<option value="${i}" ${s.sampleSource === String(i) ? "selected" : ""}>${esc(r.to)} · ${r.seconds} s</option>`).join("")}</select></label>`;
    let content = "";
    if (s.page === "portal")
      content = `<p class="subtitle">Only a marker in the installed local anchor pack can correct a position.</p><div class="scanner-frame" aria-label="Sample marker viewfinder"><span>${icon("locate")}</span><p>Offline sample anchor</p></div><div class="card"><h2>Gateway of India · Mumbai</h2><p>Explore the marker-matching flow using the included sample. No camera permission is needed.</p>${button("scan-trusted", "Match offline landmark", "primary wide")}${button("scan-unknown", "Try an unrecognized marker", "text-button wide")}</div>${s.portalResult ? `<div class="card" role="status"><h2>${s.portalResult === "trusted" ? "Trusted anchor matched" : "Marker not recognized"}</h2><p>${s.portalResult === "trusted" ? "Gateway of India · Sample pack verified. Position confidence restored." : "No matching anchor in the local pack. Position unchanged."}</p></div>` : ""}`;
    if (s.page === "outages")
      content = s.outageLog.length
        ? `${s.outageLog.map((r) => this.reportCard(r)).join("")}${button("export-outages", "Export outage log", "primary wide", "download")}`
        : `<div class="card"><h2>No outages recorded</h2><p>Run a timed GPS loss test. Completed examples appear here after recovery; cancelled tests are discarded.</p>${button("open-timed", "Simulate GNSS loss", "primary wide")}</div>`;
    if (s.page === "benchmark" || s.page === "faults") {
      content = `<p class="subtitle">${s.page === "faults" ? "Inject a fault into the sample replay and inspect the illustrated response." : "Replay a local sample with GNSS withheld, then inspect its example report."}</p>${source}`;
      if (s.page === "faults")
        content += `<fieldset class="choices"><legend>Fault</legend>${faultPresets.map(([label], i) => `<button data-action="fault-${i}" aria-pressed="${s.fault === i}">${esc(label)}</button>`).join("")}</fieldset>`;
      content += `<div class="actions">${button(s.page === "faults" ? "run-fault" : "run-benchmark", "Run", "primary")}${s.page === "faults" ? button("run-all-faults", "Run all faults", "text-button") : ""}</div>`;
      if (s.toolResult?.page === s.page) {
        content +=
          s.page === "benchmark"
            ? this.reportCard(s.toolResult.report)
            : s.toolResult.faults
                .map(
                  (i) =>
                    `<div class="card"><h2>${esc(faultPresets[i][0])}</h2><p>${esc(faultPresets[i][1])}</p><dl class="report-grid"><div><dt>Clean replay error</dt><dd>4.2 m</dd></div><div><dt>Faulted replay error</dt><dd>${(4.2 + 8 * faultPresets[i][2]).toFixed(1)} m</dd></div></dl><p>Illustrative response only</p></div>`,
                )
                .join("");
        content += button(
          "export-tool",
          "Export report",
          "outline",
          "download",
        );
      }
    }
    if (s.page === "console")
      content = `<p class="subtitle">Live values from this browser's simulated session.</p><div class="card"><div class="row"><h2>Telemetry</h2>${button("pause-diagnostics", s.diagnosticsPaused ? "Resume" : "Pause", "text-button")}</div><dl class="report-grid"><div><dt>Speed</dt><dd><span data-sensor-speed>0</span> km/h</dd></div><div><dt>Position uncertainty</dt><dd data-sensor-accuracy>±5 m</dd></div><div><dt>GNSS</dt><dd data-sensor-signal>Connected</dd></div><div><dt>Motion profile</dt><dd>${esc(s.vehicle)}</dd></div></dl></div><div class="card"><h2>Session events</h2><ol class="event-log">${s.events.map((e) => `<li>${esc(e)}</li>`).join("")}</ol>${button("clear-events", "Clear log", "text-button")}${button("export-events", "Export logs", "text-button")}</div>`;
    if (s.page === "engine")
      content = `<div class="card"><h2>GatiSaarth Navigation Engine</h2><p>v5.2 · Offline ready</p></div>${[
        [
          "Sensor fusion",
          "Satellite fixes, inertial motion, and road context inform the position estimate.",
        ],
        [
          "Motion intelligence",
          "On-device models contribute motion estimates with freshness and confidence gates.",
        ],
        [
          "Offline journey",
          "Prepared maps and saved routes keep road context available.",
        ],
        [
          "Visible limits",
          "Error grows without reliable references. Mounting, sensor quality, and outage duration affect performance.",
        ],
      ]
        .map(([h, p]) => `<div class="card"><h2>${h}</h2><p>${p}</p></div>`)
        .join(
          "",
        )}<p class="sample-note">This web replica illustrates the interface. It does not execute the Android navigation engine.</p>`;
    if (s.toolJob?.page === s.page)
      content = `<div class="card" role="status"><h2>${s.page === "portal" ? "Matching local marker" : "Replaying sample drive"}</h2><p data-job-progress>Preparing…</p><div class="progress"><span data-job-bar></span></div>${button("cancel-job", "Cancel", "text-button")}</div>`;
    return `${this.appbar(titles[s.page])}<div class="scroller">${content}${sample}</div>`;
  }
  results(query) {
    const filtered = places.filter(
      (p) =>
        p !== places[0] &&
        `${p.name} ${p.detail}`.toLowerCase().includes(query.toLowerCase()),
    );
    return filtered.length
      ? filtered
          .map(
            (p) =>
              `<button class="result" data-place="${places.indexOf(p)}">${icon("pin")}<div><strong>${esc(p.name)}</strong><small>${esc(p.detail)}</small></div></button>`,
          )
          .join("")
      : `<p class="empty">No saved place matches “${esc(query)}”. Try Gateway, Marine Drive, Churchgate, or choose on the map.</p>`;
  }
  input(event) {
    if (["from", "to"].includes(event.target.name)) {
      this.targetField = event.target.name;
      this.state[this.targetField] = null;
      this.shadowRoot.querySelector(".results").innerHTML = this.results(
        event.target.value,
      );
    }
  }
  selectPlace(place) {
    this.state[this.targetField] = place;
    if (this.state.from && this.state.to) this.prepare();
    else this.render();
  }
  prepare() {
    clearTimeout(this.planTimer);
    try {
      this.state.route = this.city.route(this.state.from, this.state.to);
    } catch (error) {
      this.notify(error.message);
      return;
    }
    this.state.page = "preparing";
    this.state.running = false;
    this.render();
    this.planTimer = setTimeout(() => {
      if (this.state.page !== "preparing") return;
      this.state.page = "preview";
      this.state.prepared = true;
      this.state.maps = true;
      this.state.progress = 0;
      this.state.pan = [0, 0];
      this.state.zoom = 1;
      this.render();
    }, 650);
  }
  back() {
    if (this.state.sheet) {
      this.state.sheet = null;
      this.renderSheet();
      return;
    }
    clearTimeout(this.planTimer);
    this.state.toolJob = null;
    if (["pick", "preview", "preparing"].includes(this.state.page)) {
      this.state.page = "plan";
      this.render();
      return;
    }
    if (this.journeyBeforePlan) {
      Object.assign(this.state, this.journeyBeforePlan);
      this.journeyBeforePlan = null;
    }
    this.state.page = null;
    this.render();
  }
  click(event) {
    const target = event.target.closest("button");
    if (!target) return;
    const s = this.state;
    if (target.dataset.tab) {
      s.tab = target.dataset.tab;
      s.page = null;
      s.sheet = null;
      this.render();
      return;
    }
    if (target.dataset.place) {
      this.selectPlace(places[Number(target.dataset.place)]);
      return;
    }
    if (target.dataset.vehicle) {
      s.vehicle = target.dataset.vehicle;
      s.automatic = false;
      this.save();
      this.render();
      return;
    }
    const action = target.dataset.action;
    if (!action) return;
    if (action.startsWith("duration-")) {
      const duration = Number(action.slice(9));
      if (outageDurations.includes(duration)) s.duration = duration;
      this.renderSheet();
      return;
    }
    if (action.startsWith("fault-")) {
      const fault = Number(action.slice(6));
      if (Number.isInteger(fault) && faultPresets[fault]) s.fault = fault;
      s.toolResult = null;
      this.render();
      return;
    }
    if (
      [
        "run-benchmark",
        "run-fault",
        "run-all-faults",
        "scan-trusted",
        "scan-unknown",
      ].includes(action)
    ) {
      s.toolJob = {
        page: s.page,
        action,
        elapsed: 0,
        source: s.sampleSource,
        fault: s.fault,
      };
      s.toolResult = null;
      this.render();
      return;
    }
    if (action === "cancel-job") {
      s.toolJob = null;
      this.render();
      return;
    }
    if (action === "clear-events") {
      s.events = [];
      this.render();
      return;
    }
    if (action === "pause-diagnostics") {
      s.diagnosticSnapshot = ["speed", "accuracy", "signal"].map(
        (key) =>
          this.shadowRoot.querySelector(`[data-sensor-${key}]`)?.textContent ||
          "—",
      );
      s.diagnosticsPaused = !s.diagnosticsPaused;
      this.render();
      return;
    }
    if (["export-outages", "export-tool", "export-events"].includes(action)) {
      this.exportJSON(
        {
          source: "GatiSaarth browser simulation · illustrative data only",
          data:
            action === "export-outages"
              ? s.outageLog
              : action === "export-tool"
                ? s.toolResult
                : s.events,
        },
        `gatisaarth-${action.slice(7)}.json`,
      );
      return;
    }
    if (action === "open-timed" || action === "timed") {
      s.sheet = "timed";
      s.lastOutage = null;
      this.renderSheet();
      return;
    }
    if (action === "start-timed") {
      this.startScenario("timed");
      return;
    }
    if (action === "cancel-outage") {
      this.finishScenario(true);
      s.sheet = null;
      this.render();
      return;
    }
    if (action === "run-again") {
      s.lastOutage = null;
      this.renderSheet();
      return;
    }
    if (
      [
        "north",
        "expand",
        "zoom-in",
        "zoom-out",
        "center",
        "swap",
        "back",
      ].includes(action)
    )
      target.setAttribute(
        "aria-label",
        {
          north: "Reset north",
          expand: "Expand app",
          "zoom-in": "Zoom in",
          "zoom-out": "Zoom out",
          center: "Recenter map",
          swap: "Swap starting point and destination",
          back: "Back",
        }[action],
      );
    if (action === "retry") {
      this.initialize();
      return;
    }
    if (action === "expand") {
      this.dispatchEvent(
        new CustomEvent("expand-app", { bubbles: true, composed: true }),
      );
      return;
    }
    if (action === "back" || action === "cancel") {
      this.back();
      return;
    }
    if (action === "plan") {
      if (!this.journeyBeforePlan) {
        if (s.recording) this.stopRecording();
        this.journeyBeforePlan = Object.fromEntries(
          ["from", "to", "route", "progress", "pan", "zoom"].map((key) => [
            key,
            s[key],
          ]),
        );
      }
      s.page = "plan";
      s.from = places[0];
      s.to = null;
      s.running = false;
      this.targetField = "to";
      this.render();
      return;
    }
    if (action === "pick") {
      s.page = "pick";
      this.picked = places[1];
      s.pan = [0, 0];
      s.zoom = 1;
      this.render();
      return;
    }
    if (action === "use-point") {
      this.selectPlace(this.picked || places[1]);
      return;
    }
    if (action === "location") {
      this.selectPlace(places[0]);
      return;
    }
    if (action === "swap") {
      [s.from, s.to] = [s.to, s.from];
      this.targetField = s.to ? "from" : "to";
      this.render();
      return;
    }
    if (action === "start") {
      if (s.scenario) this.finishScenario(true);
      this.journeyBeforePlan = null;
      s.active = true;
      s.page = null;
      s.tab = "map";
      s.progress = 0;
      s.running = true;
      s.signal = "locked";
      s.scenario = null;
      s.zoom = 3;
      s.following = true;
      s.pan = [0, 0];
      this.render();
      return;
    }
    if (action === "resume") {
      s.tab = "map";
      s.page = null;
      this.render();
      return;
    }
    if (action === "health") {
      s.tab = "sensors";
      s.page = null;
      this.render();
      return;
    }
    if (action === "drive") {
      if (s.progress >= 1) s.progress = 0;
      s.running = !s.running;
      this.render();
      return;
    }
    if (action === "end") {
      s.sheet = "end";
      this.renderSheet();
      return;
    }
    if (action === "confirm-end") {
      if (s.scenario) this.finishScenario(true);
      if (s.recording) this.stopRecording();
      s.active = false;
      s.running = false;
      s.scenario = null;
      s.signal = "locked";
      s.progress = 0;
      s.sheet = null;
      s.tab = "home";
      this.render();
      return;
    }
    if (action === "lab") {
      if (s.scenario === "tunnel" || s.scenario === "canyon") {
        this.finishScenario();
        this.render();
        return;
      }
      if (s.scenario === "timed") {
        s.sheet = "timed";
        this.renderSheet();
        return;
      }
      s.sheet = "lab";
      this.renderSheet();
      return;
    }
    if (action === "record") {
      if (s.recording) this.stopRecording();
      else {
        s.recording = true;
        s.recordSeconds = 0;
        s.recordStart = s.progress;
        s.outages = 0;
        this.notify("Drive recording started");
      }
      this.updateHUD();
      return;
    }
    if (["tunnel", "canyon"].includes(action)) {
      this.startScenario(action);
      return;
    }
    if (action === "restore") {
      this.finishScenario();
      s.sheet = null;
      this.render();
      this.notify("GNSS restored · Position realigned");
      return;
    }
    if (["zoom-in", "zoom-out"].includes(action)) {
      this.zoom(action === "zoom-in" ? 1.3 : 1 / 1.3);
      return;
    }
    if (action === "center" || action === "north") {
      s.pan = [0, 0];
      s.following = action === "center";
      s.zoom = s.following ? 3 : 1;
      this.updateMap();
      return;
    }
    if (["dark", "automatic", "haptics", "voice"].includes(action)) {
      s[action] = !s[action];
      if (action === "automatic" && s.automatic) s.vehicle = "Car";
      this.save();
      this.render();
      if (action === "voice" || action === "haptics")
        this.notify("Preference saved for this browser experience");
      return;
    }
    if (
      [
        "maps",
        "records",
        "about",
        "portal",
        "outages",
        "benchmark",
        "faults",
        "console",
        "engine",
      ].includes(action)
    ) {
      s.page = action;
      this.render();
      return;
    }
    if (action === "toggle-map") {
      s.maps = !s.maps;
      this.render();
      return;
    }
    if (action.startsWith("export-")) {
      this.exportRecord(Number(action.slice(7)));
      return;
    }
  }
  startScenario(kind) {
    const s = this.state;
    if (s.scenario) this.finishScenario(true);
    if (!s.active) {
      s.from = places[0];
      s.to = places[1];
      s.route = this.city.route(s.from, s.to);
      s.active = true;
      s.progress = 0;
    }
    if (s.progress >= 1) s.progress = 0;
    s.scenario = kind;
    s.scenarioTime = 0;
    s.scenarioStart = s.progress;
    s.signal = "lost";
    s.lastOutage = null;
    s.running = true;
    s.tab = "map";
    s.page = null;
    s.following = true;
    s.zoom = 3;
    s.outages = (s.outages || 0) + 1;
    s.sheet = kind === "timed" ? "timed" : null;
    this.logEvent(
      `${kind === "canyon" ? "Urban canyon" : kind === "timed" ? "Timed GPS loss" : "Tunnel"} test started`,
    );
    this.render();
  }
  finishScenario(cancelled = false) {
    const s = this.state;
    if (!s.scenario) return;
    if (!cancelled) {
      s.lastOutage = outageResult(
        s.scenario,
        Math.min(
          s.scenarioTime,
          s.scenario === "timed" ? s.duration : Infinity,
        ),
        Math.max(0, s.progress - s.scenarioStart) * s.route.km * 1000,
      );
      s.outageLog.unshift(s.lastOutage);
      s.outageLog = s.outageLog.slice(0, 30);
      this.logEvent("GNSS restored · Position realigned");
    } else {
      s.lastOutage = null;
      this.logEvent("Outage cancelled · Result discarded");
    }
    s.scenario = null;
    s.signal = "locked";
    this.renderSheet();
  }
  logEvent(message) {
    this.state.events.unshift(message);
    this.state.events = this.state.events.slice(0, 40);
  }
  timedSheet() {
    const s = this.state;
    if (s.scenario === "timed")
      return `<div class="sheet-content"><h2>GNSS blackout (simulated)</h2><strong class="countdown" data-countdown>${s.duration} s left</strong><p>Sample fixes are withheld while motion carries the estimated position.</p><div class="progress"><span data-outage-bar></span></div>${button("cancel-outage", "Cancel test", "outline")}${button("cancel", "View map", "text-button wide")}</div>`;
    if (s.lastOutage)
      return `<div class="sheet-content">${this.reportCard(s.lastOutage)}<div class="actions">${button("run-again", "Run again", "text-button")}${button("cancel", "Done", "primary")}</div></div>`;
    return `<div class="sheet-content"><h2>Simulate GNSS loss</h2><p>Withhold sample GPS fixes for the chosen time, run on motion estimates, then compare the result with the withheld sample.</p><div class="readiness"><span class="${s.progress > 0.1 ? "green" : "amber"}">${s.progress > 0.1 ? "✓" : "○"} <strong>Alignment:</strong> ${s.progress > 0.1 ? "Aligned with travel" : "Needs a straight drive"}</span><span>✓ <strong>IMU healthy:</strong> Accel/gyro nominal</span><span>✓ <strong>Road lock available:</strong> Mumbai route ready</span><span>✓ <strong>Velocity stable:</strong> Sample speed steady</span><span>✓ <strong>GNSS quality:</strong> Accuracy ±5 m</span></div><fieldset class="choices duration-choices"><legend>Outage duration</legend>${outageDurations.map((d) => `<button data-action="duration-${d}" aria-label="${d} s" aria-pressed="${s.duration === d}">${s.duration === d ? '<span aria-hidden="true">✓ </span>' : ""}${d} s</button>`).join("")}</fieldset>${button("start-timed", "Start", "primary wide")}${button("cancel", "Cancel", "text-button wide")}</div>`;
  }
  renderSheet() {
    const s = this.state,
      host = this.shadowRoot.querySelector(".sheet-host");
    if (!host) return;
    if (!s.sheet) {
      host.innerHTML = "";
      if (this.sheetFocus?.isConnected)
        this.sheetFocus.focus({ preventScroll: true });
      this.sheetFocus = null;
      return;
    }
    if (!host.contains(this.shadowRoot.activeElement))
      this.sheetFocus = this.shadowRoot.activeElement;
    host.innerHTML = `<div class="sheet-layer"><section class="sheet ${s.sheet === "timed" ? "timed-sheet" : "action-sheet"}" role="dialog" aria-modal="true" aria-label="${s.sheet === "lab" ? "Simulation Lab" : s.sheet === "timed" ? "Simulate GNSS loss" : "End journey"}" tabindex="-1">${s.sheet === "timed" ? this.timedSheet() : `${s.sheet === "lab" ? `<h2>Simulation Lab</h2><p>Try signal conditions while your drive recording continues. Simulations affect this app only; they do not change your device’s GNSS receiver.</p>${button("tunnel", "Tunnel test")}${button("canyon", "Urban canyon test")}${button("timed", "Timed GPS loss test")}` : `<h2>End this journey?</h2><p>Your recorded drive will remain available on this device.</p>${button("confirm-end", "End journey", "danger")}`}${button("cancel", "Cancel", "cancel")}`}</section></div>`;
    const sheet = host.querySelector(".sheet");
    sheet.focus({ preventScroll: true });
    sheet.addEventListener("keydown", (e) => {
      if (e.key !== "Tab") return;
      const buttons = [...sheet.querySelectorAll("button")];
      const first = buttons[0],
        last = buttons.at(-1);
      if (
        e.shiftKey &&
        (this.shadowRoot.activeElement === first ||
          this.shadowRoot.activeElement === sheet)
      ) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && this.shadowRoot.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    });
  }
  stopRecording() {
    const s = this.state;
    s.recording = false;
    s.records.unshift({
      to: s.to?.name || "Mumbai drive",
      seconds: Math.round(s.recordSeconds),
      km: Math.max(0, s.progress - (s.recordStart || 0)) * (s.route?.km || 0),
      outages: s.outages || 0,
      source: "GatiSaarth website simulation",
    });
    this.notify("Drive saved · Find it in Profile → Drive recordings");
  }
  exportRecord(index) {
    const record = this.state.records[index];
    if (!record) return;
    this.exportJSON(record, "gatisaarth-simulated-drive.json");
  }
  exportJSON(data, filename) {
    const url = URL.createObjectURL(
      new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  notify(message) {
    const toast = this.shadowRoot.querySelector(".toast");
    if (!toast) return;
    clearTimeout(this.toastTimer);
    toast.textContent = message;
    toast.hidden = false;
    this.toastTimer = setTimeout(() => {
      toast.hidden = true;
    }, 3500);
  }
  tick() {
    const now = performance.now(),
      dt = this.lastTick ? Math.min((now - this.lastTick) / 1000, 0.3) : 0;
    this.lastTick = now;
    if (!this.visible || document.hidden || !this.city) return;
    const s = this.state;
    if (s.recording) s.recordSeconds += dt;
    if (s.toolJob) {
      s.toolJob.elapsed += dt;
      if (s.toolJob.elapsed >= 2.4) {
        const job = s.toolJob;
        s.toolJob = null;
        if (job.page === "portal") {
          s.portalResult =
            job.action === "scan-trusted" ? "trusted" : "unknown";
          this.logEvent(
            s.portalResult === "trusted"
              ? "Sample anchor verified · Gateway of India"
              : "Unknown marker rejected",
          );
          if (s.portalResult === "trusted") this.finishScenario();
        } else {
          const recorded = s.records[Number(job.source)];
          s.toolResult = {
            page: job.page,
            source: "Illustrative browser replay",
            report: outageResult(
              "timed",
              30,
              recorded ? Math.max(1, recorded.km * 1000) : 375,
            ),
            faults:
              job.action === "run-all-faults"
                ? faultPresets.map((_, i) => i)
                : [job.fault],
          };
          this.logEvent(
            `${job.page === "faults" ? "Fault" : "Benchmark"} sample replay completed`,
          );
        }
        if (s.page === job.page) this.render();
      }
    }
    if (s.scenario) {
      s.scenarioTime += dt;
      s.signal = signalState(s.scenario, s.scenarioTime, s.duration).signal;
      if (s.scenario === "timed" && s.scenarioTime >= s.duration + 3) {
        this.finishScenario();
        this.notify("Satellite position reacquired");
      }
    }
    if (
      s.running &&
      s.active &&
      !["plan", "pick", "preview", "preparing"].includes(s.page)
    ) {
      // A deliberately accelerated sample journey, never a live GPS feed.
      s.progress = Math.min(
        1,
        s.progress +
          dt /
            (s.vehicle === "Walk" ? 170 : s.scenario === "canyon" ? 150 : 100),
      );
      if (s.progress === 1) {
        s.running = false;
        if (s.scenario) this.finishScenario(s.scenario === "timed");
        if (s.recording) this.stopRecording();
        this.render();
        this.notify(`You’ve arrived at ${s.to.name}`);
      }
    }
    if (s.following && s.running && !s.page && s.tab === "map")
      this.updateMap();
    else this.updateHUD();
  }
  updateHUD() {
    if (!this.city || !this.state.route) return;
    const s = this.state,
      root = this.shadowRoot;
    const simulation = signalState(s.scenario, s.scenarioTime, s.duration);
    const accuracy = simulation.accuracy;
    const speed = s.running
      ? s.vehicle === "Walk"
        ? 5
        : s.scenario
          ? simulation.speed
          : Math.round(43 + Math.sin(s.progress * 24) * 5)
      : 0;
    const set = (selector, text) =>
      root.querySelectorAll(selector).forEach((el) => {
        if (el.textContent !== String(text)) el.textContent = text;
      });
    set("[data-speed]", speed);
    set("[data-accuracy]", `±${accuracy} m`);
    set(
      "[data-mode]",
      s.signal === "locked" ? "GPS accuracy" : "Estimated position",
    );
    const remaining = Math.max(0, (1 - s.progress) * s.route.km);
    set(
      "[data-remaining]",
      s.active
        ? s.progress >= 1
          ? "You have arrived"
          : `${remaining.toFixed(1)} km · ${Math.max(1, Math.ceil(remaining * 3))} min`
        : "Mumbai, Maharashtra",
    );
    const point = along(s.route, s.progress),
      coordinate = unproject(point.point);
    set(
      "[data-turn-distance]",
      s.progress >= 1
        ? "Destination reached"
        : `${Math.max(10, Math.round(point.remainingM / 10) * 10)} m`,
    );
    set(
      "[data-turn]",
      s.progress >= 1
        ? s.to?.name || "Destination reached"
        : `Continue on ${point.name}`,
    );
    set(
      "[data-coordinate]",
      `${coordinate[1].toFixed(4)}°N, ${coordinate[0].toFixed(4)}°E`,
    );
    set(
      "[data-signal]",
      s.signal === "locked"
        ? "GNSS locked"
        : s.signal === "recovering"
          ? "Reacquiring GPS"
          : s.signal === "degraded"
            ? "GPS intermittent"
            : "Dead reckoning",
    );
    set(
      "[data-integrity]",
      s.signal === "locked"
        ? "● Position reliable · GNSS accuracy ±5 m"
        : s.signal === "recovering"
          ? "● GPS returning · Checking position"
          : s.signal === "degraded"
            ? `● Urban canyon · GNSS accuracy ±${accuracy} m`
            : `● Dead reckoning active · ±${accuracy} m uncertainty`,
    );
    root
      .querySelector("[data-integrity]")
      ?.classList.toggle("warning", s.signal !== "locked");
    const dot = root.querySelector("[data-signal-dot]");
    if (dot)
      dot.style.background =
        s.signal === "locked" ? "var(--blue)" : "var(--red)";
    set(
      "[data-lab-label]",
      s.scenario === "timed"
        ? "Outage"
        : s.scenario
          ? "End test"
          : "Simulation Lab",
    );
    set(
      "[data-record]",
      s.recording
        ? `Stop recording · ${Math.floor(s.recordSeconds / 60)}:${String(Math.floor(s.recordSeconds % 60)).padStart(2, "0")}`
        : "Record drive",
    );
    set(
      "[data-health-location]",
      s.signal === "locked"
        ? "GPS signal · ±5 m"
        : `Inertial estimate · ±${accuracy} m`,
    );
    set(
      "[data-health-status]",
      s.signal === "locked" ? "Connected" : "Estimated",
    );
    const svg = root.querySelector(".city-svg");
    if (svg) {
      const xy =
        s.page === "pick" && this.picked
          ? project(this.picked.point)
          : point.point;
      svg.querySelector(".position-dot").setAttribute("cx", xy[0]);
      svg.querySelector(".position-dot").setAttribute("cy", xy[1]);
      const ring = svg.querySelector(".position-ring");
      ring.setAttribute("cx", xy[0]);
      ring.setAttribute("cy", xy[1]);
      ring.setAttribute("r", s.signal === "locked" ? 14 : 14 + accuracy * 0.5);
      svg
        .querySelector(".heading-cone")
        .setAttribute(
          "transform",
          `translate(${xy[0]} ${xy[1]}) rotate(${point.heading})`,
        );
      const trail = svg.querySelector(".route-trail");
      trail.style.display = s.signal === "locked" ? "none" : "";
      if (s.signal !== "locked") {
        trail.setAttribute("d", s.route.path);
        trail.setAttribute("pathLength", "1");
        trail.style.strokeDasharray = `${s.progress} 1`;
      }
    }
    set(
      '[data-sensor="0"]',
      `${s.running ? (Math.sin(s.progress * 75) * 0.3).toFixed(2) : "0.02"} m/s²`,
    );
    set('[data-sensor="3"]', `±${accuracy} m`);
    set(
      '[data-sensor="1"]',
      `${s.running ? (Math.sin(s.progress * 20) * 0.035).toFixed(3) : "0.001"} rad/s`,
    );
    set('[data-sensor="2"]', `${Math.round((point.heading + 360) % 360)}°`);
    set('[data-sensor="5"]', s.signal === "locked" ? "Healthy" : "Estimating");
    set(
      "[data-countdown]",
      s.signal === "recovering"
        ? "Reacquiring GPS…"
        : `${Math.max(0, Math.ceil(s.duration - s.scenarioTime))} s left`,
    );
    const outageBar = root.querySelector("[data-outage-bar]");
    if (outageBar)
      outageBar.style.width = `${Math.min(100, (s.scenarioTime / s.duration) * 100)}%`;
    if (s.toolJob) {
      const progress = Math.min(
        100,
        Math.round((s.toolJob.elapsed / 2.4) * 100),
      );
      set("[data-job-progress]", `${progress}% complete`);
      const bar = root.querySelector("[data-job-bar]");
      if (bar) bar.style.width = `${progress}%`;
    }
    if (!s.diagnosticsPaused) {
      set("[data-sensor-speed]", speed);
      set("[data-sensor-accuracy]", `±${accuracy} m`);
      set(
        "[data-sensor-signal]",
        s.signal === "locked" ? "Connected" : s.signal,
      );
    } else if (s.diagnosticSnapshot) {
      ["speed", "accuracy", "signal"].forEach((key, i) =>
        set(`[data-sensor-${key}]`, s.diagnosticSnapshot[i]),
      );
    }
  }
  updateMap() {
    const svg = this.shadowRoot.querySelector(".city-svg");
    if (!svg || !this.state.route) return;
    const s = this.state;
    const area = svg.parentElement;
    const ratio = area.clientWidth / (area.clientHeight || 1);
    const points = s.route.points,
      xs = points.map((p) => p[0]),
      ys = points.map((p) => p[1]);
    let cx = (Math.min(...xs) + Math.max(...xs)) / 2,
      cy = (Math.min(...ys) + Math.max(...ys)) / 2;
    let h = Math.max(Math.max(...ys) - Math.min(...ys) + 200, 500),
      w = Math.max(Math.max(...xs) - Math.min(...xs) + 200, h * ratio);
    h = Math.max(h, w / ratio);
    w = h * ratio;
    w /= s.zoom;
    h /= s.zoom;
    if (s.following && !s.page) {
      [cx, cy] = along(s.route, s.progress).point;
      cy -= h * 0.08;
    }
    this.view = { x: cx - w / 2 - s.pan[0], y: cy - h / 2 - s.pan[1], w, h };
    svg.setAttribute("viewBox", `${this.view.x} ${this.view.y} ${w} ${h}`);
    const pixelsPerUnit = area.clientWidth / w;
    svg.style.setProperty("--map-label-size", `${9 / pixelsPerUnit}px`);
    const occupied = [];
    svg.querySelectorAll(".street-label").forEach((label, i) => {
      const item = this.city.labels[i];
      const x = (item.point[0] - this.view.x) * pixelsPerUnit;
      const y = (item.point[1] - this.view.y) * pixelsPerUnit;
      const width = item.name.length * 5.4;
      const visible =
        x >= 4 &&
        x + width <= area.clientWidth - 4 &&
        y > 16 &&
        y < area.clientHeight - 16 &&
        !occupied.some(
          (box) =>
            x < box.x + box.width + 8 &&
            x + width + 8 > box.x &&
            Math.abs(y - box.y) < 22,
        );
      if (visible) occupied.push({ x, y, width });
      const display = visible ? "" : "none";
      if (label.style.display !== display) label.style.display = display;
    });
    const route = svg.querySelector(".route-line");
    route.setAttribute("d", s.route.path);
    route.style.display =
      s.active || ["preview", "preparing"].includes(s.page) ? "" : "none";
    const dest = svg.querySelector(".destination-dot");
    dest.setAttribute("cx", points.at(-1)[0]);
    dest.setAttribute("cy", points.at(-1)[1]);
    const labels = [
      "Show entire route",
      this.expanded ? "Return to website" : "Expand app",
      "Zoom in",
      "Zoom out",
      "Recenter map",
    ];
    this.shadowRoot
      .querySelectorAll(".map-tools button")
      .forEach((b, i) => b.setAttribute("aria-label", labels[i]));
    this.shadowRoot
      .querySelectorAll(".appbar button")
      .forEach((b, i) =>
        b.setAttribute(
          "aria-label",
          i ? (this.expanded ? "Return to website" : "Expand app") : "Back",
        ),
      );
    this.shadowRoot
      .querySelector('[data-action="swap"]')
      ?.setAttribute("aria-label", "Swap starting point and destination");
    this.updateHUD();
  }
  zoom(factor) {
    this.state.zoom = Math.max(0.65, Math.min(5, this.state.zoom * factor));
    this.updateMap();
  }
  pointerDown(e) {
    const area = e.target.closest(".map-area");
    if (!area || e.target.closest("button,a")) return;
    this.pointers.set(e.pointerId, [e.clientX, e.clientY]);
    if (this.pointers.size === 2) {
      const [a, b] = [...this.pointers.values()];
      this.pinch = {
        distance: Math.hypot(a[0] - b[0], a[1] - b[1]),
        zoom: this.state.zoom,
      };
      this.drag = null;
      area.setPointerCapture(e.pointerId);
      return;
    }
    this.drag = {
      id: e.pointerId,
      x: e.clientX,
      y: e.clientY,
      pan: [...this.state.pan],
      area,
      moved: false,
    };
    area.setPointerCapture(e.pointerId);
  }
  pointerMove(e) {
    if (this.pointers.has(e.pointerId))
      this.pointers.set(e.pointerId, [e.clientX, e.clientY]);
    if (this.pinch && this.pointers.size === 2) {
      const [a, b] = [...this.pointers.values()];
      this.state.zoom = Math.max(
        0.65,
        Math.min(
          5,
          (this.pinch.zoom * Math.hypot(a[0] - b[0], a[1] - b[1])) /
            Math.max(1, this.pinch.distance),
        ),
      );
      this.updateMap();
      return;
    }
    if (!this.drag || e.pointerId !== this.drag.id) return;
    const dx = e.clientX - this.drag.x,
      dy = e.clientY - this.drag.y;
    this.drag.moved ||= Math.hypot(dx, dy) > 5;
    if (this.drag.moved && this.state.following) {
      this.state.following = false;
      const previous = this.view;
      this.state.pan = [0, 0];
      this.updateMap();
      this.drag.pan = [this.view.x - previous.x, this.view.y - previous.y];
    }
    const ratio = this.view.w / this.drag.area.getBoundingClientRect().width;
    this.state.pan = [
      this.drag.pan[0] + dx * ratio,
      this.drag.pan[1] + dy * ratio,
    ];
    this.updateMap();
  }
  pointerUp(e) {
    this.pointers.delete(e.pointerId);
    if (this.pinch) {
      this.pinch = null;
      this.drag = null;
      this.pointers.clear();
      return;
    }
    if (!this.drag || e.pointerId !== this.drag.id) return;
    if (!this.drag.moved && this.state.page === "pick") {
      const r = this.drag.area.getBoundingClientRect();
      const xy = [
        this.view.x + ((e.clientX - r.left) / r.width) * this.view.w,
        this.view.y + ((e.clientY - r.top) / r.height) * this.view.h,
      ];
      const nearest = this.city.nearest(unproject(xy));
      this.picked = {
        name: "Selected map location",
        detail: "Mumbai, Maharashtra",
        point: nearest.p,
      };
      this.updateHUD();
    }
    this.drag = null;
  }
}
customElements.define("gati-simulator", GatiSimulator);

// One app instance moves between preview and expanded view, preserving all state.
const app = document.querySelector("gati-simulator");
const mount = document.querySelector("#hero-app-mount");
const dialog = document.querySelector("#app-experience");
const expandedMount = document.querySelector("#expanded-app-mount");
let returnFocus, bodyOverflow;
function expand() {
  if (dialog.open) return;
  returnFocus = document.activeElement;
  bodyOverflow = document.body.style.overflow;
  document.body.style.overflow = "hidden";
  syncViewportHeight();
  dialog.showModal();
  expandedMount.append(app);
  app.expanded = true;
  document.querySelector("[data-close-app]").focus();
}
function syncViewportHeight() {
  const viewport = window.visualViewport;
  if (viewport && window.innerWidth <= 700 && viewport.scale === 1) {
    dialog.style.setProperty("--app-viewport-height", `${viewport.height}px`);
  } else dialog.style.removeProperty("--app-viewport-height");
}
window.visualViewport?.addEventListener("resize", () => {
  if (dialog.open) syncViewportHeight();
});
document
  .querySelectorAll("[data-experience-app]")
  .forEach((b) => b.addEventListener("click", expand));
app.addEventListener("expand-app", () =>
  dialog.open ? dialog.close() : expand(),
);
document
  .querySelector("[data-close-app]")
  .addEventListener("click", () => dialog.close());
dialog.addEventListener("click", (e) => {
  if (e.target === dialog) {
    const r = dialog.getBoundingClientRect();
    if (
      e.clientX < r.left ||
      e.clientX > r.right ||
      e.clientY < r.top ||
      e.clientY > r.bottom
    )
      dialog.close();
  }
});
dialog.addEventListener("cancel", (event) => {
  if (app.state.sheet || app.state.page) {
    event.preventDefault();
    app.back();
  }
});
dialog.addEventListener("close", () => {
  mount.append(app);
  app.expanded = false;
  app.state.running = false;
  app.render();
  document.body.style.overflow = bodyOverflow;
  returnFocus?.focus({ preventScroll: true });
});
