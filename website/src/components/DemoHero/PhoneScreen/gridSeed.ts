// Mirrors UIKitDemoSeed in examples/ios/.../UIKitDemoModels.swift so the
// website mock looks like the real app.

export interface SeedCard {
  id: string;
  title: string;
  /** width:height aspect ratio for the media area. */
  aspect: number;
  /** 0 = left column, 1 = right column. */
  column: 0 | 1;
  hue: number; // 0..1
  showsFooter: boolean;
  author?: string;
  likes?: string;
  hasPlayIcon: boolean;
}

export const SEED_CARDS: SeedCard[] = [
  {
    id: "feed-1",
    title: "Hero Spotlight",
    aspect: 193 / 257,
    column: 0,
    hue: 0.56,
    showsFooter: false,
    hasPlayIcon: false,
  },
  {
    id: "feed-2",
    title: "Starter Kit",
    aspect: 193 / 189,
    column: 0,
    hue: 0.07,
    showsFooter: false,
    hasPlayIcon: true,
  },
  {
    id: "feed-3",
    title: "How I hid my ugly HVAC panel without blocking airflow",
    aspect: 3 / 4,
    column: 0,
    hue: 0.33,
    showsFooter: true,
    author: "adrianvvlog",
    likes: "1.6K",
    hasPlayIcon: true,
  },
  {
    id: "feed-4",
    title: "Callback Bridge",
    aspect: 193 / 250,
    column: 1,
    hue: 0.75,
    showsFooter: false,
    hasPlayIcon: false,
  },
  {
    id: "feed-5",
    title: "Diffable Data",
    aspect: 252 / 189,
    column: 1,
    hue: 0.12,
    showsFooter: false,
    hasPlayIcon: true,
  },
  {
    id: "feed-6",
    title: "Compositional",
    aspect: 3 / 4,
    column: 1,
    hue: 0.95,
    showsFooter: true,
    hasPlayIcon: true,
  },
];

export interface SeedContact {
  id: string;
  name: string;
  handle: string;
  hue: number;
}

export const SEED_CONTACTS: SeedContact[] = [
  { id: "c-1", name: "autolayout_ace", handle: "@ace.2042", hue: 0.03 },
  { id: "c-2", name: "keypath_keeper", handle: "@keeper.5519", hue: 0.58 },
  { id: "c-3", name: "view_voyager", handle: "@voyager.0077", hue: 0.82 },
  { id: "c-4", name: "async_alchemist", handle: "@alchemist.3310", hue: 0.01 },
  { id: "c-5", name: "mainthread_mage", handle: "@mage.8124", hue: 0.34 },
  { id: "c-6", name: "pixel_pilot", handle: "@pilot.6601", hue: 0.66 },
  { id: "c-7", name: "debug_buddy", handle: "@buddy.9090", hue: 0.12 },
  { id: "c-8", name: "swift_wizard", handle: "@wizard.4242", hue: 0.9 },
  { id: "c-9", name: "compositional_cat", handle: "@cat.1337", hue: 0.48 },
];

/** Equivalent of UIColor(hue:saturation:brightness:alpha:) → CSS hsl(). */
export function hueToHsl(hue: number, saturation = 0.35, brightness = 0.9): string {
  const h = (hue * 360) % 360;
  const v = brightness;
  const s = saturation;
  // HSV → HSL
  const l = v * (1 - s / 2);
  const sl = l === 0 || l === 1 ? 0 : (v - l) / Math.min(l, 1 - l);
  return `hsl(${h.toFixed(0)} ${(sl * 100).toFixed(0)}% ${(l * 100).toFixed(0)}%)`;
}
