/** The demo's stand-in apps, each bound to hyper + its key. Glyphs are 24-unit stroked paths. */
export interface App {
  id: string;
  name: string;
  key: string;
  color: string;
  glyph: string;
}

export const APPS: App[] = [
  { id: 'browser', name: 'Browser', key: 'B', color: '#1f9d8b',
    glyph: 'M12 4a8 8 0 1 0 0 16a8 8 0 1 0 0-16M4 12h16M12 4c-3 3-3 13 0 16M12 4c3 3 3 13 0 16' },
  { id: 'calendar', name: 'Calendar', key: 'C', color: '#e5534b',
    glyph: 'M6 6.5h12a1.5 1.5 0 0 1 1.5 1.5v10a1.5 1.5 0 0 1-1.5 1.5H6A1.5 1.5 0 0 1 4.5 18V8A1.5 1.5 0 0 1 6 6.5M4.5 10.5h15M8.5 4v4M15.5 4v4' },
  { id: 'editor', name: 'Editor', key: 'E', color: '#7a5af5', glyph: 'M9 7.5L4.5 12L9 16.5M15 7.5l4.5 4.5l-4.5 4.5' },
  { id: 'messages', name: 'Messages', key: 'M', color: '#4a80fa',
    glyph: 'M12 5c4.4 0 8 2.9 8 6.5S16.4 18 12 18c-1 0-2-.15-2.9-.45L5 19l1.3-3.3C4.9 14.6 4 13.1 4 11.5C4 7.9 7.6 5 12 5' },
  { id: 'notes', name: 'Notes', key: 'N', color: '#d99a1e', glyph: 'M7 7.5h10M7 12h10M7 16.5h6' },
  { id: 'terminal', name: 'Terminal', key: 'T', color: '#5b616d', glyph: 'M6 8l4 4l-4 4M12.5 16.5H18' },
];
