import { useState } from "react";
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
  fadeIn,
} from "./shared";
import { PhoneWireframe, type ElementId } from "./PhoneWireframe";

// Map element IDs to JSON line indices for hover highlighting
const ELEMENT_LINES: Record<string, number[]> = {
  window: [0, 1, 2, 10, 11],
  nav: [],
  content: [3, 4, 5, 6, 9],
  text: [7],
  button: [8],
  list: [],
  "list-1": [],
  "list-2": [],
  "list-3": [],
  tab: [],
};

interface JsonLine {
  indent: number;
  content: React.ReactNode;
  elementId?: ElementId;
}

function buildJsonLines(): JsonLine[] {
  const k = (s: string) => <span className="text-violet-300">{s}</span>;
  const s = (v: string) => <span className="text-emerald-400">{v}</span>;
  const n = (v: string) => <span className="text-amber-400">{v}</span>;
  const b = (v: string) => <span className="text-zinc-600">{v}</span>;

  return [
    { indent: 0, content: b("{"), elementId: "window" },
    {
      indent: 1,
      content: <>{k('"type"')}: {s('"UIWindow"')},</>,
      elementId: "window",
    },
    {
      indent: 1,
      content: <>{k('"frame"')}: {b("{")} {n("0")}, {n("0")}, {n("390")}, {n("844")} {b("}")},</>,
      elementId: "window",
    },
    {
      indent: 1,
      content: <>{k('"children"')}: {b("[{")}</>,
      elementId: "content",
    },
    {
      indent: 2,
      content: <>{k('"type"')}: {s('"ContentView"')},</>,
      elementId: "content",
    },
    {
      indent: 2,
      content: <>{k('"frame"')}: {b("{")} {n("0")}, {n("91")}, {n("390")}, {n("663")} {b("}")},</>,
      elementId: "content",
    },
    {
      indent: 2,
      content: <>{k('"children"')}: {b("[")}</>,
      elementId: "content",
    },
    {
      indent: 3,
      content: <>{b("{")} {k('"type"')}: {s('"Text"')}, {k('"value"')}: {s('"Counter: 3"')} {b("}")},</>,
      elementId: "text",
    },
    {
      indent: 3,
      content: <>{b("{")} {k('"type"')}: {s('"Button"')}, {k('"label"')}: {s('"Increment"')} {b("}")}</>,
      elementId: "button",
    },
    { indent: 2, content: b("]"), elementId: "content" },
    { indent: 1, content: b("}]"), elementId: "window" },
    { indent: 0, content: b("}"), elementId: "window" },
  ];
}

function ConnectionBeam() {
  return (
    <div className="flex flex-col items-center gap-1.5 flex-shrink-0">
      <BeamLine />
      <span className="text-[9px] uppercase tracking-[2px] text-zinc-600 font-medium">
        remo tree
      </span>
      <BeamLine />
    </div>
  );
}

function BeamLine() {
  return (
    <div
      className="relative overflow-hidden rounded-sm"
      style={{ width: 80, height: 1.5, background: "rgba(63,63,70,0.3)" }}
    >
      <motion.div
        className="absolute top-0 h-full rounded-sm"
        style={{
          width: "60%",
          background:
            "linear-gradient(90deg, transparent, #8b5cf6, #34d399, transparent)",
        }}
        animate={{ left: ["-60%", "100%"] }}
        transition={{ duration: 2, ease: "easeInOut", repeat: Infinity }}
      />
    </div>
  );
}

export function ViewTreeSection() {
  const [hoveredId, setHoveredId] = useState<ElementId | null>(null);
  const jsonLines = buildJsonLines();

  // Which line indices should highlight
  const highlightedLines = hoveredId ? (ELEMENT_LINES[hoveredId] ?? []) : [];

  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(139,92,246,0.08)"
        secondary="rgba(52,211,153,0.06)"
      />
      <FloatingParticles
        particles={[
          { top: "20%", left: "15%", color: "#8b5cf6", duration: 6, delay: 0 },
          { top: "60%", left: "80%", color: "#34d399", duration: 8, delay: 2 },
          { top: "80%", left: "25%", color: "#8b5cf6", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="View Tree Inspection"
        labelColor="#8b5cf6"
        title="See what your agent sees"
        subtitle="Every UIView, every frame, every property — structured as JSON that agents can parse and reason about."
      />

      {/* Demo stage */}
      <div className="relative z-10 flex items-center gap-12 justify-center w-full max-w-[960px]">
        {/* Phone */}
        <motion.div {...fadeInLeft(0.2)}>
          <PhoneWireframe hoveredId={hoveredId} onHover={setHoveredId} />
        </motion.div>

        {/* Beam */}
        <motion.div {...fadeIn(0.6)}>
          <ConnectionBeam />
        </motion.div>

        {/* JSON */}
        <motion.div {...fadeInRight(0.4)} className="flex-1 min-w-0 max-w-[380px]">
          <GlassPanel glowColor="rgba(139,92,246,0.5)">
            {jsonLines.map((line, i) => (
              <div
                key={i}
                className="whitespace-nowrap transition-all duration-200 rounded px-1 -mx-1 cursor-default"
                style={{
                  paddingLeft: line.indent * 16,
                  background: highlightedLines.includes(i)
                    ? "rgba(139,92,246,0.08)"
                    : "transparent",
                  boxShadow: highlightedLines.includes(i)
                    ? "inset 2px 0 0 #8b5cf6"
                    : "none",
                }}
                onMouseEnter={() => line.elementId && setHoveredId(line.elementId)}
                onMouseLeave={() => setHoveredId(null)}
              >
                {line.content}
              </div>
            ))}
          </GlassPanel>
        </motion.div>
      </div>
    </ShowcaseSection>
  );
}
