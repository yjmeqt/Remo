import { useTimeline } from "./useTimeline";
import { IPhoneFrame } from "./IPhoneFrame";
import { CapabilityTree } from "./CapabilityTree";
import { AgentTerminal } from "./AgentTerminal";
import { ScreenshotGallery } from "./ScreenshotGallery";

export function DemoHero() {
  const {
    visibleSteps,
    activeHighlight,
    screenshots,
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

      {/* Three-column demo */}
      <div className="flex gap-4 px-5 pb-8 max-w-7xl mx-auto items-stretch">
        {/* Left: iPhone + Screenshots */}
        <div className="flex-none w-[300px] flex flex-col gap-3">
          <IPhoneFrame videoTime={currentVideoTime} />
          <div className="text-center text-violet-400 text-[10px]">
            ↓ screenshots land here ↓
          </div>
          <ScreenshotGallery
            screenshots={screenshots}
            isResetting={isResetting}
          />
        </div>

        {/* Center: Capability Tree */}
        <div className="flex-none w-[220px]">
          <CapabilityTree activeHighlight={activeHighlight} />
        </div>

        {/* Right: Agent Terminal */}
        <div className="flex-1 min-w-0">
          <AgentTerminal
            visibleSteps={visibleSteps}
            isResetting={isResetting}
          />
        </div>
      </div>
    </section>
  );
}
