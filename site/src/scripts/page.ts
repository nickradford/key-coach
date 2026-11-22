import { Island } from '../lib/island';

// The hero: the island drops from the notch once the page has loaded, and stays.
const hero = document.querySelector<HTMLElement>('.hero .island');
const heroRow = document.querySelector<HTMLTemplateElement>('template[data-hero]');
if (hero && heroRow) setTimeout(() => new Island(hero).show(heroRow.content.cloneNode(true)), 450);

// Sections materialize as they scroll into view. Without JS, or with reduced motion, CSS shows them as is.
const io = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (!entry.isIntersecting) continue;
    entry.target.classList.add('in');
    io.unobserve(entry.target);
  }
}, { rootMargin: '0px 0px -10% 0px' });
document.querySelectorAll('[data-reveal]').forEach((el) => io.observe(el));

for (const button of document.querySelectorAll<HTMLButtonElement>('[data-copy]')) {
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy!);
      button.textContent = 'Copied';
    } catch {
      getSelection()?.selectAllChildren(button.previousElementSibling!);  // let the visitor copy it by hand
      button.textContent = 'Press ⌘C';
    }
    setTimeout(() => { button.textContent = 'Copy'; }, 1600);
  });
}
