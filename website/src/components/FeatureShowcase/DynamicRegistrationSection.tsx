import { motion } from "framer-motion";
import {
  ShowcaseSection,
  SectionHeader,
  NoiseOverlay,
  AmbientLight,
  FloatingParticles,
  fadeInLeft,
  fadeInRight,
  fadeInUp,
  fadeIn,
} from "./shared";

// ---------------------------------------------------------------------------
// Capability chip
// ---------------------------------------------------------------------------

interface CapChipProps {
  name: string;
  active: boolean;
  accentColor: string;
  glowColor: string;
}

function CapChip({ name, active, accentColor, glowColor }: CapChipProps) {
  return (
    <div
      className="flex items-center gap-1.5"
      style={{
        padding: "5px 10px",
        borderRadius: 6,
        fontSize: 10,
        fontFamily: "'SF Mono','Fira Code',monospace",
        border: active
          ? `1px solid ${glowColor}`
          : "1px dashed rgba(63,63,70,0.3)",
        background: active ? `${glowColor.replace("0.3", "0.06")}` : "rgba(24,24,27,0.5)",
        opacity: active ? 1 : 0.35,
        boxShadow: active ? `0 0 12px ${glowColor.replace("0.3", "0.08")}` : "none",
      }}
    >
      <div
        className="rounded-full flex-shrink-0"
        style={{
          width: 5,
          height: 5,
          background: active ? accentColor : "#3f3f46",
          boxShadow: active ? `0 0 6px ${accentColor}` : "none",
        }}
      />
      <span style={{ color: active ? accentColor : "#52525b" }}>{name}</span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Phone wireframe (simplified, no hover interaction)
// ---------------------------------------------------------------------------

function PhoneMock({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="relative flex-shrink-0"
      style={{ width: 130, height: 260, borderRadius: 22 }}
    >
      <div
        className="absolute inset-0 overflow-hidden"
        style={{
          borderRadius: 22,
          border: "1.5px solid rgba(63,63,70,0.4)",
          background: "rgba(9,9,11,0.8)",
        }}
      >
        {/* Notch */}
        <div
          className="absolute top-[5px] left-1/2 -translate-x-1/2 z-10"
          style={{
            width: 36,
            height: 12,
            background: "#09090b",
            borderRadius: "0 0 8px 8px",
          }}
        />

        {/* Screen */}
        <div
          className="absolute overflow-hidden"
          style={{
            left: "4%",
            right: "4%",
            top: "2.5%",
            bottom: "2.5%",
            borderRadius: 18,
            background: "linear-gradient(180deg, #18181b, #1c1c20)",
          }}
        >
          {children}
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Home screen content
// ---------------------------------------------------------------------------

function HomeScreen() {
  return (
    <div className="flex flex-col h-full">
      {/* Nav */}
      <div
        className="flex items-center justify-center border-b"
        style={{
          height: 28,
          background: "rgba(63,63,70,0.2)",
          borderColor: "rgba(63,63,70,0.15)",
        }}
      >
        <span className="text-zinc-500" style={{ fontSize: 7 }}>
          My App
        </span>
      </div>

      {/* List rows */}
      <div className="flex-1 p-2 pt-3 flex flex-col gap-1">
        {[60, 90, 75, 90, 80, 85, 90, 70].map((w, i) => (
          <div
            key={i}
            className="rounded bg-zinc-700/15"
            style={{ height: 12, width: `${w}%` }}
          />
        ))}
      </div>

      {/* Bottom label */}
      <div className="text-center pb-2" style={{ fontSize: 8, color: "#52525b" }}>
        List View
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Detail screen content
// ---------------------------------------------------------------------------

function DetailScreen() {
  return (
    <div className="flex flex-col h-full">
      {/* Nav */}
      <div
        className="flex items-center border-b px-2"
        style={{
          height: 28,
          background: "rgba(63,63,70,0.2)",
          borderColor: "rgba(63,63,70,0.15)",
        }}
      >
        <div className="flex gap-1">
          <div className="w-1 h-1 rounded-full bg-zinc-600" />
          <div className="w-1 h-1 rounded-full bg-zinc-600" />
        </div>
        <span
          className="text-zinc-500 mx-auto"
          style={{ fontSize: 7 }}
        >
          Detail
        </span>
      </div>

      {/* Content */}
      <div className="flex-1 p-2 pt-3 flex flex-col items-center">
        <div
          className="mb-2"
          style={{
            width: 48,
            height: 48,
            borderRadius: 8,
            background: "rgba(167,139,250,0.1)",
            border: "1px solid rgba(167,139,250,0.2)",
          }}
        />
        <div
          className="rounded bg-zinc-700/20 mb-2 mx-auto"
          style={{ height: 10, width: "50%" }}
        />
        {[90, 85, 70].map((w, i) => (
          <div
            key={i}
            className="rounded bg-zinc-700/15 mb-1 w-full"
            style={{ height: 10, width: `${w}%` }}
          />
        ))}
        <div
          className="mt-2 flex items-center justify-center rounded-lg"
          style={{
            width: "80%",
            height: 16,
            fontSize: 6,
            fontWeight: 500,
            color: "#a78bfa",
            background: "rgba(167,139,250,0.2)",
            border: "1px solid rgba(167,139,250,0.3)",
          }}
        >
          Edit
        </div>
      </div>

      {/* Bottom label */}
      <div className="text-center pb-2" style={{ fontSize: 8, color: "#52525b" }}>
        Detail View
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Navigation arrow
// ---------------------------------------------------------------------------

function NavigationArrow() {
  return (
    <div className="flex flex-col items-center gap-1.5 mx-2 self-center">
      <AnimatedVerticalLine />
      <span
        style={{
          fontSize: 8,
          textTransform: "uppercase",
          letterSpacing: 1.5,
          color: "#52525b",
          writingMode: "vertical-rl",
          textOrientation: "mixed",
        }}
      >
        navigate
      </span>
      <AnimatedVerticalLine />
    </div>
  );
}

function AnimatedVerticalLine() {
  return (
    <div
      className="relative overflow-hidden"
      style={{ width: 1.5, height: 60, background: "rgba(63,63,70,0.3)", borderRadius: 1 }}
    >
      <motion.div
        className="absolute left-0 w-full"
        style={{
          height: "60%",
          borderRadius: 1,
          background:
            "linear-gradient(180deg, transparent, #2dd4bf, #a78bfa, transparent)",
        }}
        animate={{ top: ["-60%", "100%"] }}
        transition={{ duration: 2, ease: "easeInOut", repeat: Infinity }}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Event panel
// ---------------------------------------------------------------------------

function EventPanel() {
  return (
    <motion.div
      className="w-full max-w-[520px] mx-auto"
      style={{
        background: "rgba(24,24,27,0.7)",
        border: "1px solid rgba(63,63,70,0.3)",
        borderRadius: 10,
        padding: "12px 16px",
        fontFamily: "'SF Mono','Fira Code',monospace",
        fontSize: 10,
        lineHeight: 1.8,
      }}
      {...fadeInUp(0.6)}
    >
      <div className="text-zinc-700">
        {"// Agent receives real-time notification"}
      </div>
      <div>
        <span style={{ color: "#2dd4bf" }}>capabilities_changed</span>{" "}
        <span className="text-zinc-400">{"{"}</span>
      </div>
      <div className="pl-4">
        <span className="text-emerald-400">+ detail.getInfo</span>
      </div>
      <div className="pl-4">
        <span className="text-emerald-400">+ detail.edit</span>
      </div>
      <div className="pl-4">
        <span style={{ color: "#ef4444" }}>− list.scroll</span>
      </div>
      <div className="pl-4">
        <span style={{ color: "#ef4444" }}>− app.refresh</span>
      </div>
      <div>
        <span className="text-zinc-400">{"}"}</span>
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// DynamicRegistrationSection
// ---------------------------------------------------------------------------

const HOME_CAPS = [
  { name: "app.refresh", active: true },
  { name: "list.scroll", active: true },
  { name: "detail.getInfo", active: false },
  { name: "detail.edit", active: false },
];

const DETAIL_CAPS = [
  { name: "app.refresh", active: false },
  { name: "list.scroll", active: false },
  { name: "detail.getInfo", active: true },
  { name: "detail.edit", active: true },
];

export function DynamicRegistrationSection() {
  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(45,212,191,0.07)"
        secondary="rgba(167,139,250,0.05)"
        primaryPos="40% 35%"
        secondaryPos="60% 60%"
      />
      <FloatingParticles
        particles={[
          { top: "20%", left: "18%", color: "#2dd4bf", duration: 6, delay: 0 },
          { top: "55%", left: "80%", color: "#a78bfa", duration: 8, delay: 2 },
          { top: "82%", left: "25%", color: "#2dd4bf", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="Dynamic Registration"
        labelColor="#2dd4bf"
        title="Capabilities follow the UI"
        subtitle="Register on appear, unregister on disappear. Agents always see exactly what's available on the current screen."
      />

      <div className="relative z-10 flex flex-col items-center gap-5 w-full max-w-[960px]">
        {/* Phone columns */}
        <div className="flex items-start gap-0 justify-center">
          {/* Home column */}
          <motion.div
            className="flex flex-col items-center gap-3"
            {...fadeInLeft(0.2)}
          >
            <div
              className="font-semibold uppercase"
              style={{
                fontSize: 10,
                letterSpacing: 2,
                color: "#2dd4bf",
              }}
            >
              Home Screen
            </div>
            <PhoneMock>
              <HomeScreen />
            </PhoneMock>
            <div className="flex flex-col gap-1.5">
              {HOME_CAPS.map((c) => (
                <CapChip
                  key={c.name}
                  name={c.name}
                  active={c.active}
                  accentColor="#2dd4bf"
                  glowColor="rgba(45,212,191,0.3)"
                />
              ))}
            </div>
          </motion.div>

          {/* Navigation arrow */}
          <motion.div {...fadeIn(0.4)}>
            <NavigationArrow />
          </motion.div>

          {/* Detail column */}
          <motion.div
            className="flex flex-col items-center gap-3"
            {...fadeInRight(0.3)}
          >
            <div
              className="font-semibold uppercase"
              style={{
                fontSize: 10,
                letterSpacing: 2,
                color: "#a78bfa",
              }}
            >
              Detail Screen
            </div>
            <PhoneMock>
              <DetailScreen />
            </PhoneMock>
            <div className="flex flex-col gap-1.5">
              {DETAIL_CAPS.map((c) => (
                <CapChip
                  key={c.name}
                  name={c.name}
                  active={c.active}
                  accentColor={c.active ? "#a78bfa" : "#2dd4bf"}
                  glowColor={
                    c.active
                      ? "rgba(167,139,250,0.3)"
                      : "rgba(45,212,191,0.3)"
                  }
                />
              ))}
            </div>
          </motion.div>
        </div>

        {/* Event panel */}
        <EventPanel />
      </div>
    </ShowcaseSection>
  );
}
