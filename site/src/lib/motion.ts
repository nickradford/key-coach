// The motion values from Sources/ShortcutCoach/Motion.swift.
export const ENTER_SCALE = 0.82;
export const ENTER_BLUR = 10;
export const EXIT_BLUR = 8;
export const EXIT_MS = 260;
export const BLUR_IN_MS = 400;
export const FADE_IN_MS = 300;
export const REDUCE_FADE_MS = 200;
export const LIFT = 14;
export const ENTER = 'cubic-bezier(0.16, 1, 0.3, 1)';
export const EXIT = 'cubic-bezier(0.5, 0, 0.9, 0.5)';

// CASpringAnimation(perceptualDuration: 0.5, bounce: 0.2) is a unit-mass spring with
// natural frequency 2π / 0.5 and damping ratio 1 - 0.2.
const w0 = (2 * Math.PI) / 0.5;
const zeta = 1 - 0.2;
const wd = w0 * Math.sqrt(1 - zeta * zeta);
const at = (t: number) => 1 - Math.exp(-zeta * w0 * t) * (Math.cos(wd * t) + ((zeta * w0) / wd) * Math.sin(wd * t));

/** Until the spring is within 0.1% of rest, like CASpringAnimation.settlingDuration. */
export const SPRING_MS = Math.round((1000 * Math.log(1000 / Math.sqrt(1 - zeta * zeta))) / (zeta * w0));

const steps = 60;
/** The spring as a CSS easing, for WAAPI and transitions alike. */
export const SPRING = `linear(${Array.from({ length: steps + 1 }, (_, i) =>
  i === steps ? 1 : +at((i / steps) * (SPRING_MS / 1000)).toFixed(4),
).join(', ')})`;
