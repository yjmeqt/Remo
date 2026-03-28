import { useTimeline } from "./useTimeline";
import { IPhoneFrame } from "./IPhoneFrame";
import { AgentTerminal } from "./AgentTerminal";

export function DemoHero() {
  const {
    visibleSteps,
    currentVideoTime,
    isResetting,
  } = useTimeline();

  return (
    <section>
      {/* Tagline */}
      <div className="text-center py-8 px-6">
        <h1 className="text-3xl md:text-4xl font-bold tracking-tight text-zinc-50">
          Eyes and hands for AI agents on iOS
        </h1>
        <p className="text-zinc-500 mt-2 text-sm">
          Watch Claude Code drive an iOS app through Remo — autonomously.
        </p>
      </div>

      {/* TODO: responsive layout — stack vertically on mobile (currently desktop-only) */}
      {/* Two-column demo — fixed height from iPhone (300 * 920/450 ≈ 613px) */}
      <div className="flex gap-4 px-5 pb-8 max-w-5xl mx-auto h-[613px]">
        {/* Left: iPhone */}
        <div className="flex-none h-full">
          <IPhoneFrame videoTime={currentVideoTime} />
        </div>

        {/* Right: Agent Terminal — aligned with iPhone screen area (2.5% top/bottom) */}
        <div className="flex-1 min-w-0 mt-[15px] h-[582px]">
          <AgentTerminal
            visibleSteps={visibleSteps}
            isResetting={isResetting}
          />
        </div>
      </div>
    </section>
  );
}
