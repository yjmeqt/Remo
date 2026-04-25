import type { AccentColorName } from "../timeline";

/** Match the AppStore.accentColor mapping in the iOS sample. */
export const ACCENT_COLORS: Record<AccentColorName, string> = {
  blue: "#0a84ff",
  purple: "#bf5af2",
  red: "#ff453a",
  green: "#30d158",
  orange: "#ff9f0a",
  pink: "#ff375f",
  yellow: "#ffd60a",
  mint: "#63e6e2",
  teal: "#40c8e0",
};

/** Tailwind-friendly liquid-glass classes — translucent tint + blur + saturation. */
export const LIQUID_GLASS =
  "backdrop-blur-xl backdrop-saturate-150 bg-white/55 border border-white/40 shadow-[0_1px_0_rgba(255,255,255,0.6)_inset,0_8px_24px_rgba(0,0,0,0.08)]";
