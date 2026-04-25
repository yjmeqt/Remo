import { motion, AnimatePresence } from "framer-motion";
import type { PhoneState } from "../useTimeline";
import { ACCENT_COLORS } from "./colors";
import { StatusBar } from "./StatusBar";
import { TabBar } from "./TabBar";
import { HomeScreen } from "./HomeScreen";
import { GridScreen } from "./GridScreen";
import { Toast } from "./Toast";
import { Confetti } from "./Confetti";

interface PhoneScreenProps {
  state: PhoneState;
}

export function PhoneScreen({ state }: PhoneScreenProps) {
  const accent = ACCENT_COLORS[state.accentColor];

  return (
    <div className="absolute inset-0 bg-[#f2f2f7] text-zinc-900">
      <StatusBar />

      <div className="absolute inset-x-0 top-[26px] bottom-[58px] overflow-hidden">
        <AnimatePresence mode="wait">
          {state.route === "home" && (
            <motion.div
              key="home"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.2 }}
              className="absolute inset-0"
            >
              <HomeScreen accent={accent} />
            </motion.div>
          )}
          {state.route === "uikit" && (
            <motion.div
              key="grid"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.2 }}
              className="absolute inset-0"
            >
              <GridScreen
                tab={state.gridTab}
                scroll={state.gridScroll}
                appendedCards={state.appendedCards}
              />
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      <Toast message={state.toastMessage} accent={accent} />
      <Confetti active={state.showConfetti} triggerKey={state.confettiKey} />

      <TabBar route={state.route} accent={accent} />
    </div>
  );
}
