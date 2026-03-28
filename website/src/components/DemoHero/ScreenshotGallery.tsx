import { motion, AnimatePresence } from "framer-motion";

interface ScreenshotGalleryProps {
  screenshots: number[];
  isResetting: boolean;
}

const SCREENSHOT_LABELS = ["screenshot_001", "screenshot_002"];

export function ScreenshotGallery({
  screenshots,
  isResetting,
}: ScreenshotGalleryProps) {
  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-3">
      <div className="text-[9px] font-semibold uppercase tracking-wider text-zinc-500 mb-2">
        Captured
      </div>
      <div className="grid grid-cols-2 gap-2">
        <AnimatePresence mode="popLayout">
          {!isResetting &&
            screenshots.map((idx) => (
              <motion.div
                key={idx}
                layoutId={`screenshot-${idx}`}
                initial={{ opacity: 0, scale: 0.5, y: -60 }}
                animate={{ opacity: 1, scale: 1, y: 0 }}
                exit={{ opacity: 0, scale: 0.8 }}
                transition={{ type: "spring", stiffness: 300, damping: 25 }}
                className="h-14 bg-[#09090b] border border-emerald-500/30 rounded flex items-center justify-center shadow-[0_0_8px_rgba(52,211,153,0.1)]"
              >
                <span className="text-emerald-400 text-[9px]">
                  {SCREENSHOT_LABELS[idx] ?? `screenshot_${idx + 1}`}
                </span>
              </motion.div>
            ))}
        </AnimatePresence>
        {Array.from({ length: Math.max(0, 2 - screenshots.length) }).map(
          (_, i) => (
            <div
              key={`empty-${i}`}
              className="h-14 bg-[#09090b] border border-dashed border-zinc-800 rounded flex items-center justify-center"
            >
              <span className="text-zinc-700 text-sm">+</span>
            </div>
          )
        )}
      </div>
    </div>
  );
}
