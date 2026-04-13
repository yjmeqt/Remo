import { useState, useEffect, useRef } from "react";
import {
  DEMO_STEPS,
  DEMO_TOTAL_DURATION,
  VIDEO_PHASE_START,
  VIDEO_OFFSET,
} from "./timeline";

export interface TimelineState {
  visibleSteps: typeof DEMO_STEPS;
  currentVideoTime: number;
  isResetting: boolean;
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

  // Video is hidden (videoTime = -1) until VIDEO_PHASE_START, and during reset.
  // Once active, it plays continuously with VIDEO_OFFSET to skip the recording
  // startup idle period so the video starts right when capabilities fire.
  const currentVideoTime =
    elapsed >= VIDEO_PHASE_START && !isResetting
      ? elapsed - VIDEO_PHASE_START + VIDEO_OFFSET
      : -1;

  return {
    visibleSteps,
    currentVideoTime,
    isResetting,
  };
}
