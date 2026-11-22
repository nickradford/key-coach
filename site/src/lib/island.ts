import {
  BLUR_IN_MS, ENTER, ENTER_BLUR, ENTER_SCALE, EXIT, EXIT_BLUR, EXIT_MS, FADE_IN_MS, LIFT, REDUCE_FADE_MS, SPRING, SPRING_MS,
} from './motion';

export const reducedMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

const spring: KeyframeAnimationOptions = { duration: SPRING_MS, easing: SPRING };
const exit: KeyframeAnimationOptions = { duration: EXIT_MS, easing: EXIT, fill: 'forwards' };

const stop = (el: Element) => el.getAnimations().forEach((a) => a.cancel());

/** Entrance: scales up, sharpens from a blur and fades in, on the island's spring. */
export function materialize(el: HTMLElement, from = '') {
  el.animate({ transform: [`${from} scale(${ENTER_SCALE})`, 'none'] }, spring);
  el.animate({ filter: [`blur(${ENTER_BLUR}px)`, 'blur(0px)'] }, { duration: BLUR_IN_MS, easing: ENTER });
  el.animate({ opacity: [0, 1] }, { duration: FADE_IN_MS, easing: ENTER });
}

/** Exit: the entrance in reverse, quicker. The element stays invisible afterwards. */
export function dematerialize(el: HTMLElement) {
  const { transform, opacity } = getComputedStyle(el);
  stop(el);
  return el
    .animate({ transform: [transform, `scale(${ENTER_SCALE})`], filter: ['blur(0px)', `blur(${EXIT_BLUR}px)`], opacity: [opacity, '0'] }, exit)
    .finished;
}

const SHAPE = ['width', 'height', 'borderBottomLeftRadius', 'borderBottomRightRadius', 'transform'] as const;
const snapshot = (el: HTMLElement) => {
  const style = getComputedStyle(el);
  return Object.fromEntries(SHAPE.map((p) => [p, style[p]]));
};

/**
 * A black island that grows out of the notch: Island.swift on the web. CSS holds both shapes,
 * the notch (data-state hidden or hiding) and the island around its content (shown);
 * every change animates from the shape on screen to the new one.
 */
export class Island {
  private body: HTMLElement;
  private parts: HTMLElement[];
  private generation = 0;

  constructor(private root: HTMLElement) {
    this.body = root.querySelector('.island-body')!;
    this.parts = [this.body, ...root.querySelectorAll<HTMLElement>('.ear')];
  }

  /** Shows `node` under the notch. When the island is already up, the content is swapped in place. */
  show(node: Node) {
    this.generation++;
    const swap = this.root.dataset.state === 'shown';
    const opacity = getComputedStyle(this.root).opacity;
    const before = this.parts.map(snapshot);
    [this.root, ...this.parts].forEach(stop);
    const content = document.createElement('div');
    content.className = 'island-content';
    content.append(node);
    this.body.replaceChildren(content);
    this.root.dataset.state = 'shown';
    if (reducedMotion()) {
      if (!swap) this.root.animate({ opacity: [opacity, '1'] }, REDUCE_FADE_MS);
      return;
    }
    const after = this.parts.map(snapshot);
    this.parts.forEach((el, i) => el.animate([before[i], after[i]], spring));
    if (!swap) {
      const k = parseFloat(getComputedStyle(this.root).getPropertyValue('--k')) || 1;
      materialize(content, `translateY(${-LIFT * k}px)`);  // starts a little up and settles
    }
  }

  /** Retracts into the notch, then takes the content away. */
  hide() {
    if (this.root.dataset.state !== 'shown') return;
    const mine = ++this.generation;
    const content = this.body.firstElementChild as HTMLElement;
    const before = this.parts.map(snapshot);
    this.parts.forEach(stop);
    this.root.dataset.state = 'hiding';
    let done: Promise<unknown>;
    if (reducedMotion()) {
      done = this.root.animate({ opacity: [1, 0] }, { duration: EXIT_MS, fill: 'forwards' }).finished;
    } else {
      const after = this.parts.map(snapshot);
      this.parts.forEach((el, i) => el.animate([before[i], after[i]], exit));
      done = dematerialize(content);
    }
    done.then(() => {
      if (mine !== this.generation) return;  // shown again meanwhile
      this.root.dataset.state = 'hidden';
      [this.root, ...this.parts].forEach(stop);
      content.remove();
    }, () => {});
  }
}
