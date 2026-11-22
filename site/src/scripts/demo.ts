import { APPS, type App } from '../lib/apps';
import { fluency, HOLD, type Outcome, type Stage } from '../lib/fluency';
import { dematerialize, Island, materialize, reducedMotion } from '../lib/island';

const GUIDE_DELAY = 700;  // HoldTracker.delay
const WEIGHT = 4;  // each switch in the demo counts as four attempts, so an app is learned in five hotkey presses
const CELEBRATE_HOLD = 2;  // Flash.celebrate
const FIRST_ORDER = ['editor', 'browser', 'notes', 'messages', 'calendar', 'terminal'];  // front to back
const STAGE_NAME: Record<Stage, string> = { learning: 'Learning', practicing: 'Practicing', fluent: 'Fluent', learned: 'Learned' };

type Source = 'alt' | 'caps' | 'button';

/** The try-it demo: a fake desktop where clicks are misses and hyper + letter is a hit, scored as the app scores them. */
export function initDemo(demo: HTMLElement) {
  const q = (s: string) => demo.querySelector<HTMLElement>(s)!;
  const desktop = q('.desktop');
  const menuApp = q('.menu-app');
  const readout = q('.readout');
  const hyperButton = q('.hyper-btn');
  const flashIsland = new Island(q('.island.flash'));
  const guideIsland = new Island(q('.island.guide'));
  const windows = new Map(APPS.map((a) => [a.id, q(`.win[data-app="${a.id}"]`)]));
  const dockItems = new Map(APPS.map((a) => [a.id, q(`.dock-item[data-app="${a.id}"]`)]));
  const appById = new Map(APPS.map((a) => [a.id, a]));
  const appByCode = new Map(APPS.map((a) => [`Key${a.key}`, a]));
  const template = (s: string) => (q(s) as HTMLTemplateElement).content.cloneNode(true) as DocumentFragment;

  let records = new Map<string, Outcome[]>();
  let celebrated = new Set<string>();
  let order: string[] = [];
  let hidden = new Set<string>();

  const keysHTML = (app: App) => `<span aria-hidden="true">⇪ ${app.key}</span><span class="sr">Caps Lock ${app.key}</span>`;
  const say = (html: string) => { readout.innerHTML = html; };

  function render() {
    order.forEach((id, i) => {
      const win = windows.get(id)!;
      win.style.zIndex = String(order.length - i);
      win.classList.toggle('front', i === 0);
      win.toggleAttribute('data-hidden', hidden.has(id));
    });
    menuApp.textContent = appById.get(order[0])!.name;
    for (const app of APPS) {
      const stage = fluency(records.get(app.id)!);
      const item = dockItems.get(app.id)!;
      item.dataset.stage = stage;
      item.setAttribute('aria-label', `${app.name}, hotkey Caps Lock ${app.key}, ${STAGE_NAME[stage]}`);
    }
  }

  // The miss flash (Flash.swift): `hold` runs from the start of the drop to the start of the retract.
  let flashGeneration = 0;
  function flash(app: App, hold: number, label?: string) {
    const mine = ++flashGeneration;
    const row = template(`template[data-flash="${app.id}"]`);
    if (label) {
      const span = document.createElement('span');
      span.className = 'label';
      span.textContent = label;
      row.firstElementChild!.append(span);
    }
    flashIsland.show(row);
    setTimeout(() => { if (mine === flashGeneration) flashIsland.hide(); }, hold * 1000);  // a newer flash restarts the hold
  }

  /** `app` comes to the front. A switch the long way is a miss; one with the hotkey is a hit. */
  function activate(app: App, byHotkey: boolean) {
    if (app.id === order[0]) return;  // already in front: no switch, nothing to coach
    const history = records.get(app.id)!;
    const before = fluency(history);
    history.push(...Array<Outcome>(WEIGHT).fill(byHotkey ? 'hit' : 'miss'));
    const after = fluency(history);
    order = [app.id, ...order.filter((id) => id !== app.id)];
    hidden.delete(app.id);
    render();
    if (held.size) {
      activatedDuringHold = true;
      closeGuide();
    }
    const now = after === before ? STAGE_NAME[after] : `Now ${STAGE_NAME[after]}`;
    if (!byHotkey) {
      const hold = HOLD[before];
      if (hold) flash(app, hold);
      say(hold
        ? `${app.name} the long way: its hotkey is ${keysHTML(app)}. Flashed for ${hold} s. ${now}.`
        : `${app.name} the long way. Learned, so no flash. ${now}.`);
    } else if (after === 'learned' && !celebrated.has(app.id)) {
      celebrated.add(app.id);  // once per history, as justGraduated
      flash(app, CELEBRATE_HOLD, '✓ Learned');
      say(`${keysHTML(app)}: ${app.name} is learned. Clicking it won’t flash now.`);
    } else {
      say(`${keysHTML(app)}: ${app.name}, no flash. ${now}.`);
    }
  }

  /** Hyper + F: Tinycast hides every app but the front one. */
  function hideOthers() {
    hidden = new Set(order.slice(1));
    render();
    if (guideOpen) {
      hideBadges();
      showBadges();
    }
  }

  // The hold guide (Guide.swift, HoldTracker): opens after hyper is held 0.7 s with no switch,
  // closes on release or when a bound app comes forward, and stays closed until the next press.
  const held = new Set<Source>();
  let activatedDuringHold = false;
  let guideTimer = 0;
  let guideOpen = false;
  let badges: HTMLElement[] = [];

  function setHeld(source: Source, on: boolean) {
    const was = held.size > 0;
    if (on) held.add(source);
    else held.delete(source);
    const is = held.size > 0;
    demo.classList.toggle('hyper-held', is);
    if (is && !was) {
      activatedDuringHold = false;
      guideTimer = window.setTimeout(() => { if (!activatedDuringHold) openGuide(); }, GUIDE_DELAY);
    } else if (!is && was) {
      clearTimeout(guideTimer);
      closeGuide();
    }
  }
  const releaseAll = () => (['alt', 'caps', 'button'] as const).forEach((s) => setHeld(s, false));

  function openGuide() {
    guideOpen = true;
    guideIsland.show(template('template[data-guide]'));
    showBadges();
  }

  function closeGuide() {
    if (!guideOpen) return;
    guideOpen = false;
    guideIsland.hide();
    hideBadges();
  }

  /** A letter badge at the centre of each visible window, unless a nearer window covers that point (badgePoints). */
  function showBadges() {
    const base = desktop.getBoundingClientRect();
    const shown = order.filter((id) => !hidden.has(id)).map((id) => ({ id, r: windows.get(id)!.getBoundingClientRect() }));
    shown.forEach(({ id, r }, i) => {
      const x = r.left + r.width / 2, y = r.top + r.height / 2;
      if (shown.slice(0, i).some(({ r: o }) => x >= o.left && x <= o.right && y >= o.top && y <= o.bottom)) return;
      const badge = document.createElement('div');
      badge.className = 'badge';
      badge.textContent = appById.get(id)!.key;
      badge.style.left = `${x - base.left}px`;
      badge.style.top = `${y - base.top}px`;
      desktop.append(badge);
      badges.push(badge);
      if (!reducedMotion()) materialize(badge);
    });
  }

  function hideBadges() {
    const leaving = badges;
    badges = [];
    for (const badge of leaving) {
      if (reducedMotion()) badge.remove();
      else dematerialize(badge).then(() => badge.remove(), () => badge.remove());
    }
  }

  function reset() {
    records = new Map(APPS.map((a) => [a.id, []]));
    celebrated = new Set();
    order = [...FIRST_ORDER];
    hidden = new Set();
    flashGeneration++;
    flashIsland.hide();
    releaseAll();
    render();
  }

  // Keys count only while focus is inside the demo, so the page around it keeps its keyboard.
  // ⌘ and ⌃ shortcuts pass through unless all four modifiers are down (Tinycast's hyper).
  const isHyper = (e: KeyboardEvent) =>
    (e.metaKey && e.ctrlKey && e.altKey && e.shiftKey) ||
    (!e.metaKey && !e.ctrlKey && (e.altKey || e.getModifierState('CapsLock') || held.size > 0));

  demo.addEventListener('keydown', (e) => {
    if (e.key === 'Alt') {
      e.preventDefault();  // keeps Windows browsers from focusing their menu bar
      setHeld('alt', true);
      return;
    }
    if (!e.altKey) setHeld('alt', false);
    if (e.key === 'CapsLock') return setHeld('caps', true);
    if (e.repeat || !isHyper(e)) return;
    const app = appByCode.get(e.code);
    if (app) {
      e.preventDefault();
      activate(app, true);
    } else if (e.code === 'KeyF') {
      e.preventDefault();
      hideOthers();
    }
  });
  demo.addEventListener('keyup', (e) => {
    if (e.key === 'Alt') e.preventDefault();
    if (e.key === 'Alt' || !e.altKey) setHeld('alt', false);
    // Browsers report Caps Lock as it locks and unlocks, so here it works as a toggle.
    if (e.key === 'CapsLock') setHeld('caps', false);
  });
  demo.addEventListener('focusout', (e) => { if (!demo.contains(e.relatedTarget as Node | null)) releaseAll(); });
  window.addEventListener('blur', releaseAll);

  // A click lands focus in the demo even where it hits no button, and Safari never focuses buttons on click.
  demo.addEventListener('pointerdown', () => {
    if (!demo.contains(document.activeElement)) demo.focus({ preventScroll: true });
  });

  // A click on a window or Dock icon is the long way, unless hyper is held: then it stands in for the letter.
  let suppressClickUntil = 0;
  demo.addEventListener('click', (e) => {
    const app = appById.get((e.target as Element).closest<HTMLElement>('[data-app]')?.dataset.app ?? '');
    if (app && e.timeStamp > suppressClickUntil) activate(app, held.size > 0);
  });
  // A second finger may get no click while the first holds ⇪, so take the tap on pointerup.
  demo.addEventListener('pointerup', (e) => {
    const app = appById.get((e.target as Element).closest<HTMLElement>('[data-app]')?.dataset.app ?? '');
    if (!app || e.pointerType === 'mouse' || !held.has('button')) return;
    suppressClickUntil = e.timeStamp + 500;
    activate(app, true);
  });

  // The on-screen ⇪: press and hold with a pointer, or hold Space while it has focus.
  hyperButton.addEventListener('pointerdown', (e) => {
    setHeld('button', true);
    hyperButton.setPointerCapture(e.pointerId);  // the release still lands here if the finger slides off
  });
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    hyperButton.addEventListener(type, () => setHeld('button', false));
  }
  hyperButton.addEventListener('keydown', (e) => {
    if (e.code !== 'Space') return;
    e.preventDefault();
    setHeld('button', true);
  });
  hyperButton.addEventListener('keyup', (e) => {
    if (e.code !== 'Space') return;
    e.preventDefault();
    setHeld('button', false);
  });
  hyperButton.addEventListener('contextmenu', (e) => e.preventDefault());

  q('.reset').addEventListener('click', () => {
    reset();
    say('Reset. Every app is back to Learning.');
  });
  reset();
}
