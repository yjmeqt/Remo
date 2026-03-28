import { useState, useEffect, useRef, useCallback } from "react";
import { DEMO_STEPS, DEMO_TOTAL_DURATION } from "./timeline";
import type { DemoStep } from "./timeline";

export interface TimelineState {
  visibleSteps: DemoStep[];
  activeHighlight: string | null;
  screenshots: number[];
  currentVideoTime: number;
  isResetting: boolean;
}

export function useTimeline(): TimelineState {
  const [elapsed, setElapsed] = useState(0);
  const [isResetting, setIsResetting] = useState(false);
  const startTimeRef = useRef(Date.now());
  const frameRef = useRef<number>(0);

  const tick = useCallback(() => {
    const now = Date.now();
    const rawElapsed = (now - startTimeRef.current) / 1000;

    if (rawElapsed >= DEMO_TOTAL_DURATION) {
      setIsResetting(true);
      setTimeout(() => {
        startTimeRef.current = Date.now();
        setElapsed(0);
        setIsResetting(false);
      }, 2000);
      return;
    }

    setElapsed(rawElapsed);
    frameRef.current = requestAnimationFrame(tick);
  }, []);

  useEffect(() => {
    frameRef.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frameRef.current);
  }, [tick]);

  const visibleSteps = DEMO_STEPS.filter((step) => step.time <= elapsed);

  const lastHighlightStep = [...visibleSteps]
    .reverse()
    .find((s) => s.treeHighlight);
  const activeHighlight = lastHighlightStep?.treeHighlight ?? null;
  const highlightAge = lastHighlightStep
    ? elapsed - lastHighlightStep.time
    : Infinity;
  const displayHighlight = highlightAge < 2.5 ? activeHighlight : null;

  const screenshots = visibleSteps
    .filter((s) => s.screenshot)
    .map((_, i) => i);

  const lastVideoStep = [...visibleSteps]
    .reverse()
    .find((s) => s.videoTime !== undefined);
  const currentVideoTime = lastVideoStep?.videoTime ?? 0;

  return {
    visibleSteps,
    activeHighlight: displayHighlight,
    screenshots,
    currentVideoTime,
    isResetting,
  };
}
