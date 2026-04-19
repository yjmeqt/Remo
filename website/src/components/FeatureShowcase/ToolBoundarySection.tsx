import { motion } from "framer-motion";
import {
  ShowcaseSection,
  SectionHeader,
  GlassPanel,
  NoiseOverlay,
  AmbientLight,
  FloatingParticles,
  fadeInLeft,
  fadeInRight,
  fadeInUp,
} from "./shared";

interface BoundaryPanelProps {
  title: string;
  accent: string;
  glowColor: string;
  items: string[];
}

function BoundaryPanel({ title, accent, glowColor, items }: BoundaryPanelProps) {
  return (
    <GlassPanel glowColor={glowColor} className="h-full">
      <div
        className="inline-flex items-center gap-2 rounded-md px-3 py-1 text-[10px] font-semibold uppercase tracking-[2px]"
        style={{
          color: accent,
          background: `${accent}1a`,
          border: `1px solid ${accent}33`,
        }}
      >
        <span
          className="h-[6px] w-[6px] rounded-full"
          style={{ background: accent, boxShadow: `0 0 8px ${accent}` }}
        />
        {title}
      </div>

      <div className="mt-6 flex flex-col gap-3 font-sans text-sm leading-relaxed text-zinc-300">
        {items.map((item) => (
          <div
            key={item}
            className="rounded-xl border border-zinc-800/80 bg-zinc-950/30 px-4 py-3"
          >
            {item}
          </div>
        ))}
      </div>
    </GlassPanel>
  );
}

export function ToolBoundarySection() {
  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(56,189,248,0.07)"
        secondary="rgba(52,211,153,0.05)"
        primaryPos="35% 38%"
        secondaryPos="68% 60%"
      />
      <FloatingParticles
        particles={[
          { top: "20%", left: "18%", color: "#38bdf8", duration: 6, delay: 0 },
          { top: "62%", left: "82%", color: "#34d399", duration: 8, delay: 2 },
          { top: "84%", left: "30%", color: "#38bdf8", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="Tool Boundary"
        labelColor="#38bdf8"
        title="Use Remo inside the app. Use xcodebuildmcp around it."
        subtitle="xcodebuildmcp already handles simulator automation, screenshots, recording, and broader inspection well. Remo focuses on app-defined capabilities and semantic runtime control."
      />

      <div className="relative z-10 grid w-full max-w-5xl gap-6 md:grid-cols-2">
        <motion.div {...fadeInLeft(0.2)}>
          <BoundaryPanel
            title="xcodebuildmcp"
            accent="#38bdf8"
            glowColor="rgba(56,189,248,0.5)"
            items={[
              "Simulator automation and UI control",
              "Screenshots and screen recordings",
              "Broader inspection and debugging workflows",
              "Tooling outside the running app boundary",
            ]}
          />
        </motion.div>

        <motion.div {...fadeInRight(0.35)}>
          <BoundaryPanel
            title="Remo"
            accent="#34d399"
            glowColor="rgba(52,211,153,0.5)"
            items={[
              "App-defined capability registration",
              "Structured runtime invocation",
              "Semantic state changes inside the app",
              "Discovery across USB devices and Bonjour simulators",
            ]}
          />
        </motion.div>
      </div>

      <motion.p
        className="relative z-10 mt-8 max-w-3xl text-center text-sm leading-relaxed text-zinc-500"
        {...fadeInUp(0.5)}
      >
        Remo starts where generic simulator tooling stops: inside the running app,
        with the app's own semantics, state transitions, and lifecycle-aware capabilities.
      </motion.p>
    </ShowcaseSection>
  );
}
