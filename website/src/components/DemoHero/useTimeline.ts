import { useState, useEffect, useRef } from "react";
import {
  DEMO_STEPS,
  DEMO_TOTAL_DURATION,
  PHONE_ACTION_DELAY,
  PHONE_BOOT_TIME,
  type AccentColorName,
  type GridTab,
  type PhoneRoute,
  type ScrollPosition,
} from "./timeline";

export interface AppendedCard {
  id: string;
  title: string;
  subtitle: string;
}

export interface PhoneState {
  /** False before PHONE_BOOT_TIME and during reset — screen reads as off. */
  isOn: boolean;
  route: PhoneRoute;
  accentColor: AccentColorName;
  toastMessage: string | null;
  /** Increments every confetti trigger so the overlay can re-mount. */
  confettiKey: number;
  showConfetti: boolean;
  gridTab: GridTab;
  gridScroll: Record<GridTab, ScrollPosition>;
  appendedCards: AppendedCard[];
}

export interface TimelineState {
  visibleSteps: typeof DEMO_STEPS;
  phoneState: PhoneState;
  isResetting: boolean;
}

const TOAST_DURATION = 3.0;
const CONFETTI_DURATION = 2.5;

const INITIAL_PHONE_STATE: PhoneState = {
  isOn: false,
  route: "home",
  accentColor: "blue",
  toastMessage: null,
  confettiKey: 0,
  showConfetti: false,
  gridTab: "feed",
  gridScroll: { feed: "top", items: "top" },
  appendedCards: [],
};

function derivePhoneState(elapsed: number, isResetting: boolean): PhoneState {
  if (isResetting) return INITIAL_PHONE_STATE;

  const state: PhoneState = {
    ...INITIAL_PHONE_STATE,
    isOn: elapsed >= PHONE_BOOT_TIME,
    gridScroll: { ...INITIAL_PHONE_STATE.gridScroll },
    appendedCards: [],
  };

  let confettiTriggers = 0;
  let lastToastTime = -Infinity;
  let lastConfettiTime = -Infinity;

  for (const step of DEMO_STEPS) {
    if (!step.phoneAction) continue;
    const fireTime = step.time + PHONE_ACTION_DELAY;
    if (fireTime > elapsed) continue;

    switch (step.phoneAction.kind) {
      case "toast":
        state.toastMessage = step.phoneAction.message;
        lastToastTime = fireTime;
        break;
      case "setAccentColor":
        state.accentColor = step.phoneAction.color;
        break;
      case "confetti":
        confettiTriggers += 1;
        lastConfettiTime = fireTime;
        break;
      case "navigate":
        state.route = step.phoneAction.route;
        break;
      case "selectGridTab":
        state.gridTab = step.phoneAction.tab;
        break;
      case "gridScroll":
        state.gridScroll[state.gridTab] = step.phoneAction.position;
        break;
      case "feedAppend":
        state.appendedCards.push({
          id: `appended-${state.appendedCards.length}`,
          title: step.phoneAction.title,
          subtitle: step.phoneAction.subtitle,
        });
        break;
    }
  }

  state.confettiKey = confettiTriggers;
  state.showConfetti =
    confettiTriggers > 0 && elapsed - lastConfettiTime < CONFETTI_DURATION;

  if (state.toastMessage && elapsed - lastToastTime >= TOAST_DURATION) {
    state.toastMessage = null;
  }

  return state;
}

// TODO: pause animation when tab is not visible (Page Visibility API)
// TODO: pause on hover so users can read terminal output
export function useTimeline(): TimelineState {
  const [elapsed, setElapsed] = useState(0);
  const [isResetting, setIsResetting] = useState(false);
  const startTimeRef = useRef<number>(0);
  const frameRef = useRef<number>(0);
  const timeoutRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => {
    startTimeRef.current = Date.now();

    const tick = () => {
      const now = Date.now();
      const rawElapsed = (now - startTimeRef.current) / 1000;

      if (rawElapsed >= DEMO_TOTAL_DURATION) {
        setIsResetting(true);
        timeoutRef.current = setTimeout(() => {
          startTimeRef.current = Date.now();
          setElapsed(0);
          setIsResetting(false);
          frameRef.current = requestAnimationFrame(tick);
        }, 2000);
        return;
      }

      setElapsed(rawElapsed);
      frameRef.current = requestAnimationFrame(tick);
    };

    frameRef.current = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(frameRef.current);
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, []);

  const visibleSteps = DEMO_STEPS.filter((step) => step.time <= elapsed);
  const phoneState = derivePhoneState(elapsed, isResetting);

  return {
    visibleSteps,
    phoneState,
    isResetting,
  };
}
