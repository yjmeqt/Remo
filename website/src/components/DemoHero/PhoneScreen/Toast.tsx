import { motion, AnimatePresence } from "framer-motion";

interface ToastProps {
  message: string | null;
  accent: string;
}

export function Toast({ message, accent }: ToastProps) {
  return (
    <AnimatePresence>
      {message && (
        <motion.div
          key={message}
          initial={{ y: -20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          exit={{ y: -20, opacity: 0 }}
          transition={{ type: "spring", duration: 0.4 }}
          className="absolute top-[52px] left-1/2 -translate-x-1/2 z-30 flex items-center gap-2 px-4 py-2.5 rounded-full text-white text-[12px] font-medium shadow-[0_4px_18px_rgba(0,0,0,0.18)] backdrop-blur-xl backdrop-saturate-150"
          style={{
            background: `${accent}d9`,
            WebkitBackdropFilter: "blur(20px) saturate(150%)",
          }}
        >
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
            <path
              d="M5 12c1-1.5 3.5-3 7-3s6 1.5 7 3M3 9c1.5-2 5-4 9-4s7.5 2 9 4M7 15c.5-1 2-2 5-2s4.5 1 5 2M12 19h.01"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
              className="text-white/80"
            />
          </svg>
          {message}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
