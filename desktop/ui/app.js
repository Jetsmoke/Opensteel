// The Opensteel window: key cards, DPI, polling, lighting and the write button, talking
// to the Rust side through Tauri commands. Opened in a plain browser it runs against a
// stand-in mouse, for previewing the layout.

import {
  actionCatalog, actionName, actionValue, parseAction, sameAction, DISABLED,
  mainSlots, sideSlotsInGridOrder, allSlots, actionForKey, actionForMouseButton, isMouseClick,
} from "./catalog.js";
import { MouseModel3D } from "./model3d.js";

const tauri = window.__TAURI__;
const invoke = tauri ? tauri.core.invoke : previewInvoke;

const CPI_MIN = 100, CPI_MAX = 18000, CPI_SLIDER_MAX = 5000;
const POLLING_RATES = [125, 250, 500, 1000];
// Bluetooth LE reports at most every 7.5 ms, so the mouse runs at 133 Hz there whatever
// polling rate is stored (measured on a real Aerox 9).
const BLUETOOTH_POLLING = 133;
const CONNECTION_LABELS = {
  none: "Not connected", usb: "USB cable", dongle: "2.4 GHz dongle", bluetooth: "Bluetooth", noaccess: "No permission",
};
const NO_ACCESS_MESSAGE = "Linux needs a udev rule to reach the mouse. Install the .deb or .rpm, or see the Opensteel page.";

const state = {
  settings: null,
  defaults: null,
  connection: "none",
  battery: null,
  selected: null,
  hovered: null,
  flashing: new Set(),
  writeState: "idle",  // idle | writing | saved
  message: "",
  isError: false,
  // Lighting is only written once it has been changed here, so writing buttons never
  // disturbs lighting someone set up elsewhere.
  lightingChanged: false,
  lastOnBluetooth: readStored("lastOnBluetooth") === "true",
};

const $ = (id) => document.getElementById(id);
const editable = () => state.connection !== "none" && state.connection !== "noaccess";
const actionFor = (id) => state.settings.mapping[id] ?? DISABLED;

let model3d;

// MARK: - Startup

async function start() {
  const accent = (await invoke("accent_colour").catch(() => null)) || getComputedStyle(document.documentElement).getPropertyValue("--accent").trim();
  document.documentElement.style.setProperty("--accent", accent);
  [state.settings, state.defaults] = await Promise.all([invoke("load_settings"), invoke("default_settings")]);

  buildCards($("side-grid"), sideSlotsInGridOrder);
  buildCards($("main-grid"), mainSlots);
  buildSliders();
  buildLighting();
  buildActions();

  model3d = new MouseModel3D($("mouse3d"), accent);
  await model3d.load("assets/Aerox9.mesh").catch((e) => console.error("model", e));

  await refreshConnection();
  render();
  await fitWindow();
  setInterval(refreshConnection, 1500);
  setInterval(refreshBattery, 30000);
  refreshBattery();
  listenForPresses();
}

/** Sizes the window to the page and shows it. */
async function fitWindow() {
  if (!tauri) return;
  const win = tauri.window.getCurrentWindow();
  const height = Math.ceil(document.getElementById("app").getBoundingClientRect().height);
  const size = new tauri.dpi.LogicalSize(660, height);
  await win.setSize(size);
  await win.show();
  // Linux ignores sizing a window before it is shown, so check once it is up.
  await new Promise((r) => setTimeout(r, 50));
  if (Math.abs(window.innerHeight - height) > 1) await win.setSize(size);
}

async function refreshConnection() {
  const now = await invoke("connection").catch(() => "none");
  const changed = now !== state.connection;
  state.connection = now;
  if (now !== "none" && now !== "noaccess" && (now === "bluetooth") !== state.lastOnBluetooth) {
    state.lastOnBluetooth = now === "bluetooth";
    writeStored("lastOnBluetooth", String(state.lastOnBluetooth));
  }
  if (changed) {
    if (now === "noaccess") { state.message = NO_ACCESS_MESSAGE; state.isError = true; }
    else if (state.message === NO_ACCESS_MESSAGE) { state.message = ""; state.isError = false; }
    if (!editable()) state.battery = null;
    else refreshBattery();
    render();
  }
}

async function refreshBattery() {
  if (!editable() || state.writeState === "writing") return;
  state.battery = await invoke("battery").catch(() => null);
  renderHeader();
}

// MARK: - Building the page

function buildCards(container, slots) {
  for (const slot of slots) {
    const card = document.createElement("div");
    card.className = "card";
    card.dataset.id = slot.id;
    card.innerHTML = `<span class="slot"></span><span class="value"></span><select></select>`;
    card.querySelector(".slot").textContent = slot.label;
    const select = card.querySelector("select");
    select.addEventListener("change", () => {
      setAction(slot.id, parseAction(select.value.replace(/^default:/, "")));
    });
    // The picker opening is the selection; key presses keep working while it's open.
    select.addEventListener("mousedown", () => { state.selected = slot.id; renderHighlights(); });
    card.addEventListener("mouseenter", () => { state.hovered = slot.id; renderHighlights(); });
    card.addEventListener("mouseleave", () => { if (state.hovered === slot.id) { state.hovered = null; renderHighlights(); } });
    card.addEventListener("click", () => { if (!editable()) { state.selected = slot.id; renderHighlights(); } });
    container.append(card);
  }
}

function fillPicker(select, id) {
  const current = actionFor(id);
  select.replaceChildren();
  let found = false;
  for (const group of actionCatalog) {
    const og = document.createElement("optgroup");
    og.label = group.name;
    for (const o of group.options) {
      const opt = new Option(o.name, actionValue(o.action));
      if (sameAction(o.action, current)) { opt.selected = true; found = true; }
      og.append(opt);
    }
    select.append(og);
  }
  const fallback = state.defaults.mapping[id] ?? DISABLED;
  const og = document.createElement("optgroup");
  og.label = "Default";
  og.append(new Option(`Default (${actionName(fallback)})`, `default:${actionValue(fallback)}`));
  if (!found) og.append(new Option(actionName(current), actionValue(current), true, true));
  select.append(og);
}

function sliderRow(container, { min, max, unit, onSlide, onType }) {
  container.innerHTML = `<input type="range" step="any"><input class="number" inputmode="numeric"><span class="unit"></span>`;
  const [range, number] = container.querySelectorAll("input");
  range.min = min; range.max = max;
  container.querySelector(".unit").textContent = unit;
  range.addEventListener("input", () => onSlide(Number(range.value)));
  const commit = () => { const n = parseInt(number.value, 10); if (!Number.isNaN(n)) onType(n); render(); };
  number.addEventListener("change", commit);
  number.addEventListener("keydown", (e) => { if (e.key === "Enter") { commit(); number.blur(); } });
  return { range, number };
}

let cpiRow, pollingRow;
function buildSliders() {
  cpiRow = sliderRow($("cpi-row"), {
    min: CPI_MIN, max: CPI_SLIDER_MAX, unit: "DPI",
    onSlide: (v) => { state.settings.cpi = Math.round(v / 100) * 100; markDirty(); renderSliders(); },
    onType: (n) => {
      state.settings.cpi = Math.min(Math.max(Math.round(n / 100) * 100, CPI_MIN), CPI_MAX);
      markDirty();
    },
  });
  $("cpi-row").title = "Type any value from 100 to 18000";
  const nearest = (hz) => POLLING_RATES.reduce((a, b) => (Math.abs(b - hz) < Math.abs(a - hz) ? b : a));
  pollingRow = sliderRow($("polling-row"), {
    min: 0, max: 1000, unit: "Hz",
    onSlide: (v) => { state.settings.pollingRate = nearest(v); markDirty(); renderSliders(); },
    onType: (n) => { state.settings.pollingRate = nearest(n); markDirty(); },
  });
}

function buildLighting() {
  const setCycle = (on) => { state.settings.colourCycle = on; markLightingDirty(); render(); };
  $("lights-off").addEventListener("click", () => setCycle(false));
  $("lights-cycle").addEventListener("click", () => setCycle(true));
  $("flash").addEventListener("change", (e) => { state.settings.clickFlash = e.target.checked; markLightingDirty(); render(); });
  // The colour picker and the hex field edit the same stored hex.
  $("flash-picker").addEventListener("input", (e) => {
    state.settings.clickFlashHex = e.target.value.slice(1).toUpperCase();
    markLightingDirty();
    renderLighting();
  });
  $("flash-hex").addEventListener("input", (e) => {
    const cleaned = e.target.value.toUpperCase().replace(/[^0-9A-F]/g, "").slice(0, 6);
    e.target.value = cleaned;
    state.settings.clickFlashHex = cleaned;
    markLightingDirty();
    renderLighting();
  });
}

function buildActions() {
  $("reset").addEventListener("click", () => { $("confirm").hidden = false; $("confirm-cancel").focus(); });
  $("confirm-cancel").addEventListener("click", () => { $("confirm").hidden = true; });
  $("confirm-reset").addEventListener("click", () => { $("confirm").hidden = true; resetDefaults(); });
  $("write").addEventListener("click", writeToMouse);
}

// MARK: - Rendering

function render() {
  renderHeader();
  renderCards();
  renderSliders();
  renderLighting();
  renderActions();
  renderHighlights();
}

function renderHeader() {
  const pill = $("pill");
  pill.className = `pill ${state.connection}`;
  pill.innerHTML = `<span class="dot"></span><span></span>`;
  pill.lastChild.textContent = CONNECTION_LABELS[state.connection];
  if (!editable()) pill.insertAdjacentHTML("beforeend", `<span class="sep">·</span>${lockIcon}<span>View only</span>`);

  const battery = $("battery");
  battery.hidden = !state.battery;
  if (state.battery) {
    const { percent, charging } = state.battery;
    battery.className = `battery${percent <= 15 && !charging ? " low" : ""}`;
    battery.title = charging ? "Charging" : "Battery";
    battery.innerHTML = `${batteryIcon(percent, charging)}<span>${percent}%</span>`;
  }
}

function renderCards() {
  for (const card of document.querySelectorAll(".card")) {
    const id = card.dataset.id;
    card.querySelector(".value").textContent = actionName(actionFor(id));
    const select = card.querySelector("select");
    select.disabled = !editable();
    fillPicker(select, id);
  }
}

function renderSliders() {
  const { cpi, pollingRate } = state.settings;
  cpiRow.range.value = Math.min(cpi, CPI_SLIDER_MAX);
  if (document.activeElement !== cpiRow.number) cpiRow.number.value = cpi;

  const bluetooth = state.connection === "bluetooth" || (!editable() && state.lastOnBluetooth);
  const shown = bluetooth ? BLUETOOTH_POLLING : pollingRate;
  pollingRow.range.value = shown;
  if (document.activeElement !== pollingRow.number) pollingRow.number.value = shown;

  const lockPolling = state.connection === "bluetooth" || !editable();
  $("cpi-row").classList.toggle("locked", !editable());
  $("polling-row").classList.toggle("locked", lockPolling);
  // A locked row ignores clicks rather than being disabled, which would grey the slider;
  // its box carries the explanation.
  $("cpi-row").parentElement.title = editable() ? "" : "Connect the mouse to edit.";
  $("polling-row").parentElement.title = !editable() ? "Connect the mouse to edit."
    : state.connection === "bluetooth" ? `Bluetooth is locked to ${BLUETOOTH_POLLING} Hz. Set to ${pollingRate} Hz for USB and 2.4 GHz.` : "";
}

function renderLighting() {
  const s = state.settings;
  $("lights-off").setAttribute("aria-checked", String(!s.colourCycle));
  $("lights-cycle").setAttribute("aria-checked", String(s.colourCycle));
  $("flash").checked = s.clickFlash;
  $("flash-colour").hidden = !s.clickFlash;
  if (document.activeElement !== $("flash-hex")) $("flash-hex").value = s.clickFlashHex;
  if (/^[0-9A-F]{6}$/i.test(s.clickFlashHex)) $("flash-picker").value = `#${s.clickFlashHex.toLowerCase()}`;
  const box = $("lighting");
  box.classList.toggle("locked-area", !editable());
  box.title = editable() ? "" : "Connect the mouse to edit.";
}

function renderActions() {
  $("reset").disabled = !editable();
  const write = $("write");
  write.disabled = !editable() || state.writeState === "writing";
  write.classList.toggle("saved", state.writeState === "saved");
  $("write-label").innerHTML = {
    idle: "Write to Mouse",
    writing: `<span class="spinner"></span>Writing…`,
    saved: "✓ Saved",
  }[state.writeState];
  const message = $("message");
  message.textContent = state.message;
  message.classList.toggle("error", state.isError);
}

function renderHighlights() {
  for (const card of document.querySelectorAll(".card")) {
    const id = card.dataset.id;
    card.classList.toggle("selected", state.selected === id);
    card.classList.toggle("hovered", state.hovered === id && state.selected !== id);
    card.classList.toggle("flashing", state.flashing.has(id));
  }
  model3d?.highlight({ selected: state.selected, hovered: state.hovered, flashing: state.flashing });
}

// MARK: - Editing and writing

function markDirty() {
  state.message = "Unsaved changes. Click “Write to Mouse” to apply.";
  state.isError = false;
  renderActions();
}

function markLightingDirty() {
  state.lightingChanged = true;
  markDirty();
}

function setAction(id, action) {
  state.settings.mapping[id] = action;
  markDirty();
  renderCards();
}

function resetDefaults() {
  state.settings = structuredClone(state.defaults);
  state.lightingChanged = true;
  state.message = "Defaults restored here. Click “Write to Mouse” to apply.";
  state.isError = false;
  render();
}

async function writeToMouse() {
  const s = state.settings;
  if (state.lightingChanged && s.clickFlash && !/^[0-9A-F]{6}$/i.test(s.clickFlashHex)) {
    state.message = "The reactive colour needs six hex digits, like FF8800.";
    state.isError = true;
    renderActions();
    return;
  }
  if (state.writeState === "writing") return;
  state.writeState = "writing";
  state.message = "";
  state.isError = false;
  renderActions();
  const lighting = state.lightingChanged;
  try {
    await invoke("write_settings", { settings: s, lighting });
    if (lighting) state.lightingChanged = false;
    state.writeState = "saved";
    state.message = "Saved to the mouse.";
    renderActions();
    setTimeout(() => { if (state.writeState === "saved") { state.writeState = "idle"; renderActions(); } }, 2000);
  } catch (e) {
    state.writeState = "idle";
    state.message = String(e);
    state.isError = true;
    renderActions();
  }
}

// MARK: - Highlighting presses

let flashTimer;
function flash(ids) {
  // A key bound to a mouse click is usually being used to click something in this
  // window, so it only flashes; taking the selection would fight with that click.
  const first = ids.find((id) => !isMouseClick(actionFor(id)));
  if (first) state.selected = first;
  state.flashing = new Set(ids);
  renderHighlights();
  clearTimeout(flashTimer);
  flashTimer = setTimeout(() => { state.flashing = new Set(); renderHighlights(); }, 350);
}

/** Over the cable and the dongle the side buttons just type their keys, so a key that
 *  matches a binding highlights that button instead of doing anything here. */
function listenForPresses() {
  const matching = (action) => allSlots.map((s) => s.id).filter((id) => sameAction(actionFor(id), action));
  window.addEventListener("keydown", (e) => {
    if (e.target.matches?.("input.number, input.hex") || !$("confirm").hidden) return;
    const action = actionForKey(e);
    const ids = action ? matching(action) : [];
    if (!ids.length) return;
    e.preventDefault();
    if (!e.repeat) flash(ids);
  }, true);
  window.addEventListener("mousedown", (e) => {
    const action = actionForMouseButton(e.button);
    const ids = action ? matching(action) : [];
    if (!ids.length) return;
    e.preventDefault();
    flash(ids);
  }, true);
}

// MARK: - Icons

const lockIcon = `<svg width="10" height="12" viewBox="0 0 10 12" aria-hidden="true"><rect x="0.5" y="5" width="9" height="6.5" rx="1.5" fill="currentColor"/><path d="M2.5 5V3.5a2.5 2.5 0 0 1 5 0V5" fill="none" stroke="currentColor" stroke-width="1.3"/></svg>`;

function batteryIcon(percent, charging) {
  const w = Math.max(1.5, 15 * percent / 100);
  const bolt = charging ? `<path d="M10 2.2 7.2 7h2.3L8.4 9.8 11.4 5H9.1z" fill="var(--bg)" stroke="var(--bg)" stroke-width="0.6"/><path d="M10 2.2 7.2 7h2.3L8.4 9.8 11.4 5H9.1z" fill="currentColor"/>` : "";
  return `<svg width="24" height="12" viewBox="0 0 24 12" aria-hidden="true">
    <rect x="0.5" y="0.5" width="19" height="11" rx="3" fill="none" stroke="currentColor" opacity="0.6"/>
    <rect x="21" y="4" width="1.8" height="4" rx="0.9" fill="currentColor" opacity="0.6"/>
    <rect x="2.5" y="2.5" width="${w}" height="7" rx="1.5" fill="currentColor"/>${bolt}</svg>`;
}

// MARK: - Helpers

function readStored(key) { try { return localStorage.getItem(key); } catch { return null; } }
function writeStored(key, value) { try { localStorage.setItem(key, value); } catch { /* not kept */ } }

/** A stand-in mouse for opening the page in a browser. */
async function previewInvoke(command) {
  const sample = {
    mapping: {
      S1: { type: 81, code: 58 }, S2: { type: 81, code: 59 }, S3: { type: 81, code: 60 }, S4: { type: 81, code: 62 },
      S5: { type: 81, code: 63 }, S6: { type: 81, code: 35 }, S7: { type: 81, code: 36 }, S8: { type: 81, code: 37 },
      S9: { type: 81, code: 38 }, S10: { type: 1, code: 0 }, S11: { type: 81, code: 45 }, S12: { type: 81, code: 41 },
      B3: { type: 3, code: 0 }, CPI: { type: 0, code: 0 }, SU: { type: 49, code: 0 }, SD: { type: 50, code: 0 },
    },
    cpi: 1400, pollingRate: 1000, colourCycle: false, clickFlash: false, clickFlashHex: "FFFFFF",
  };
  const defaults = structuredClone(sample);
  [0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2D, 0x2E]
    .forEach((code, i) => { defaults.mapping[`S${i + 1}`] = { type: 81, code }; });
  defaults.cpi = 800;
  const params = new URLSearchParams(location.search);
  switch (command) {
    case "accent_colour": return null;
    case "load_settings": return params.has("defaults") ? defaults : sample;
    case "default_settings": return defaults;
    case "connection": return params.get("connection") ?? "usb";
    case "battery": return { percent: 95, charging: false };
    case "write_settings": await new Promise((r) => setTimeout(r, 600)); return null;
  }
}

start();
