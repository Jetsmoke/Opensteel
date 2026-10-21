// What a button can be bound to, the mouse's button slots, and how key presses map
// back to HID usages. Mirrors the Mac app's tables.

const key = (usage) => ({ type: 0x51, code: usage });
const media = (usage) => ({ type: 0x61, code: usage });
const mouse = (n) => ({ type: n, code: 0 });
export const DISABLED = { type: 0x00, code: 0 };

const keys = (list) => list.map(([name, usage]) => ({ name, action: key(usage) }));
const range = (from, to) => Array.from({ length: to - from + 1 }, (_, i) => from + i);

export const actionCatalog = [
  { name: "Special", options: [
    { name: "Disabled", action: DISABLED },
    { name: "Scroll up", action: { type: 0x31, code: 0 } },
    { name: "Scroll down", action: { type: 0x32, code: 0 } },
    { name: "Scroll left", action: { type: 0x33, code: 0 } },
    { name: "Scroll right", action: { type: 0x34, code: 0 } },
  ] },
  { name: "Mouse", options: [
    { name: "Left click", action: mouse(1) },
    { name: "Right click", action: mouse(2) },
    { name: "Middle click", action: mouse(3) },
    { name: "Back (button 4)", action: mouse(4) },
    { name: "Forward (button 5)", action: mouse(5) },
    { name: "Button 6", action: mouse(6) },
    { name: "Button 7", action: mouse(7) },
    { name: "Button 8", action: mouse(8) },
  ] },
  { name: "Media", options: [
    { name: "Play / Pause", action: media(0xCD) },
    { name: "Next track", action: media(0xB5) },
    { name: "Previous track", action: media(0xB6) },
    { name: "Volume up", action: media(0xE9) },
    { name: "Volume down", action: media(0xEA) },
    { name: "Mute", action: media(0xE2) },
  ] },
  { name: "Letters", options: keys(range(0, 25).map((i) => [String.fromCharCode(65 + i), 0x04 + i])) },
  { name: "Numbers", options: keys([...range(1, 9).map((n) => [`${n}`, 0x1D + n]), ["0", 0x27]]) },
  { name: "Symbols", options: keys([
    ["-", 0x2D], ["=", 0x2E], ["[", 0x2F], ["]", 0x30], ["\\", 0x31],
    [";", 0x33], ["'", 0x34], ["`", 0x35], [",", 0x36], [".", 0x37], ["/", 0x38],
  ]) },
  { name: "Editing & navigation", options: keys([
    ["Enter", 0x28], ["Escape", 0x29], ["Backspace", 0x2A], ["Delete", 0x4C], ["Tab", 0x2B], ["Space", 0x2C],
    ["Up arrow", 0x52], ["Down arrow", 0x51], ["Left arrow", 0x50], ["Right arrow", 0x4F],
    ["Home", 0x4A], ["End", 0x4D], ["Page up", 0x4B], ["Page down", 0x4E], ["Caps lock", 0x39],
  ]) },
  { name: "Modifiers", options: keys([
    ["Ctrl (left)", 0xE0], ["Ctrl (right)", 0xE4], ["Shift (left)", 0xE1], ["Shift (right)", 0xE5],
    ["Alt (left)", 0xE2], ["Alt (right)", 0xE6], ["Win / Super (left)", 0xE3], ["Win / Super (right)", 0xE7],
  ]) },
  { name: "Function keys", options: keys([
    ...range(1, 12).map((n) => [`F${n}`, 0x39 + n]),
    ...range(13, 24).map((n) => [`F${n}`, 0x5B + n]),
  ]) },
  { name: "Keypad", options: keys([
    ...range(1, 9).map((n) => [`Keypad ${n}`, 0x58 + n]),
    ["Keypad 0", 0x62], ["Keypad .", 0x63], ["Keypad /", 0x54], ["Keypad *", 0x55],
    ["Keypad -", 0x56], ["Keypad +", 0x57], ["Keypad Enter", 0x58],
  ]) },
];

export const sameAction = (a, b) => a.type === b.type && (a.code ?? 0) === (b.code ?? 0);
export const actionValue = (a) => `${a.type}:${a.code ?? 0}`;
export const parseAction = (v) => { const [type, code] = v.split(":").map(Number); return { type, code }; };

export function actionName(a) {
  for (const g of actionCatalog) {
    const o = g.options.find((o) => sameAction(o.action, a));
    if (o) return o.name;
  }
  const hex = (n) => n.toString(16).toUpperCase().padStart(2, "0");
  return `Custom (0x${hex(a.type)} 0x${hex(a.code ?? 0)})`;
}

// Left and right click are never remapped.
export const mainSlots = [
  { id: "B3", label: "Wheel click" },
  { id: "CPI", label: "Top button" },
  { id: "SU", label: "Scroll up" },
  { id: "SD", label: "Scroll down" },
];
export const sideSlots = range(1, 12).map((n) => ({ id: `S${n}`, label: `Side ${n}` }));
export const allSlots = [...mainSlots, ...sideSlots];

// The side grid is 4 buttons long and 3 tall, numbered up each column from the
// front-bottom (1-2-3, 4-5-6, …) to 12 at the back-top.
const columns = 4, rows = 3;
export const sideSlotsInGridOrder = range(0, rows - 1).flatMap((row) =>
  range(0, columns - 1).map((column) => sideSlots[column * rows + (rows - 1 - row)]));

// KeyboardEvent.code → what the mouse would have to send for it.
const codeToUsage = (() => {
  const m = {};
  range(0, 25).forEach((i) => { m[`Key${String.fromCharCode(65 + i)}`] = 0x04 + i; });
  range(1, 9).forEach((n) => { m[`Digit${n}`] = 0x1D + n; m[`Numpad${n}`] = 0x58 + n; });
  range(1, 12).forEach((n) => { m[`F${n}`] = 0x39 + n; });
  range(13, 24).forEach((n) => { m[`F${n}`] = 0x5B + n; });
  Object.assign(m, {
    Digit0: 0x27, Enter: 0x28, Escape: 0x29, Backspace: 0x2A, Tab: 0x2B, Space: 0x2C,
    Minus: 0x2D, Equal: 0x2E, BracketLeft: 0x2F, BracketRight: 0x30, Backslash: 0x31,
    Semicolon: 0x33, Quote: 0x34, Backquote: 0x35, Comma: 0x36, Period: 0x37, Slash: 0x38,
    CapsLock: 0x39, Home: 0x4A, PageUp: 0x4B, Delete: 0x4C, End: 0x4D, PageDown: 0x4E,
    ArrowRight: 0x4F, ArrowLeft: 0x50, ArrowDown: 0x51, ArrowUp: 0x52,
    NumpadDivide: 0x54, NumpadMultiply: 0x55, NumpadSubtract: 0x56, NumpadAdd: 0x57,
    NumpadEnter: 0x58, Numpad0: 0x62, NumpadDecimal: 0x63,
    ControlLeft: 0xE0, ShiftLeft: 0xE1, AltLeft: 0xE2, MetaLeft: 0xE3,
    ControlRight: 0xE4, ShiftRight: 0xE5, AltRight: 0xE6, MetaRight: 0xE7,
  });
  return m;
})();

const mediaCodes = {
  MediaPlayPause: 0xCD, MediaTrackNext: 0xB5, MediaTrackPrevious: 0xB6,
  AudioVolumeUp: 0xE9, AudioVolumeDown: 0xEA, AudioVolumeMute: 0xE2,
};

/** The action a key event corresponds to, or null. */
export function actionForKey(event) {
  if (event.code in codeToUsage) return key(codeToUsage[event.code]);
  if (event.code in mediaCodes) return media(mediaCodes[event.code]);
  return null;
}

/** The action a mouse button press corresponds to (left/right clicks are just clicks). */
export function actionForMouseButton(button) {
  return { 1: mouse(3), 3: mouse(4), 4: mouse(5) }[button] ?? null;
}

export const isMouseClick = (a) => a.type >= 1 && a.type <= 8 && (a.code ?? 0) === 0;
