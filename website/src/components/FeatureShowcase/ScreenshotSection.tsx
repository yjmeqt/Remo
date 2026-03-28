import { motion } from "framer-motion";
import {
  ShowcaseSection,
  SectionHeader,
  NoiseOverlay,
  AmbientLight,
  FloatingParticles,
  fadeInUp,
} from "./shared";

// ---------------------------------------------------------------------------
// Phone with shutter flash
// ---------------------------------------------------------------------------

function ShutterPhone() {
  return (
    <div
      className="relative flex-shrink-0"
      style={{ width: 160, height: 320, borderRadius: 28 }}
    >
      {/* Phone body */}
      <div
        className="absolute inset-0 overflow-hidden"
        style={{
          borderRadius: 28,
          border: "1.5px solid rgba(63,63,70,0.4)",
          background: "rgba(9,9,11,0.8)",
        }}
      >
        {/* Notch */}
        <div
          className="absolute top-[6px] left-1/2 -translate-x-1/2 z-10"
          style={{
            width: 44,
            height: 15,
            background: "#09090b",
            borderRadius: "0 0 10px 10px",
          }}
        />

        {/* Screen */}
        <div
          className="absolute overflow-hidden flex flex-col"
          style={{
            left: "4%",
            right: "4%",
            top: "2.5%",
            bottom: "2.5%",
            borderRadius: 22,
            background: "linear-gradient(180deg, #18181b, #1c1c20)",
            padding: "36px 10px 10px",
          }}
        >
          {/* Shutter flash overlay */}
          <motion.div
            className="absolute inset-0 pointer-events-none"
            style={{ borderRadius: 22, background: "rgba(244,114,182,0.12)" }}
            animate={{
              opacity: [0, 0, 0, 0, 1, 0, 0],
            }}
            transition={{
              duration: 3,
              times: [0, 0.8, 0.84, 0.85, 0.87, 0.92, 1],
              repeat: Infinity,
              ease: "easeInOut",
            }}
          />

          {/* Captured badge */}
          <motion.div
            className="absolute top-[38px] right-[12px] z-20"
            style={{
              fontSize: 8,
              textTransform: "uppercase",
              letterSpacing: 1.5,
              fontWeight: 600,
              color: "#f472b6",
              background: "rgba(244,114,182,0.15)",
              border: "1px solid rgba(244,114,182,0.25)",
              padding: "2px 6px",
              borderRadius: 4,
            }}
            animate={{
              opacity: [0, 0, 0, 0, 1, 1, 0, 0],
              scale: [0.9, 0.9, 0.9, 0.9, 1, 1, 0.9, 0.9],
            }}
            transition={{
              duration: 3,
              times: [0, 0.8, 0.84, 0.85, 0.87, 0.95, 0.97, 1],
              repeat: Infinity,
              ease: "easeInOut",
            }}
          >
            Captured
          </motion.div>

          {/* Nav bar */}
          <div className="h-[14px] rounded bg-zinc-700/30 mb-2" />

          {/* Counter */}
          <div className="text-[28px] font-bold text-center text-white my-6">
            4
          </div>

          {/* Button */}
          <div
            className="w-[70%] mx-auto h-7 rounded-lg flex items-center justify-center text-[10px] font-medium"
            style={{
              background: "rgba(139,92,246,0.3)",
              border: "1px solid rgba(139,92,246,0.4)",
              color: "#c084fc",
            }}
          >
            Increment
          </div>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Thumbnail strip
// ---------------------------------------------------------------------------

const THUMBS = [
  { num: 1, value: "1", active: false },
  { num: 2, value: "2", active: false },
  { num: 3, value: "3", active: false },
  { num: 4, value: "4", active: true },
];

function ThumbnailStrip() {
  return (
    <div className="flex gap-2.5 items-center justify-center">
      {THUMBS.map((t, i) => (
        <motion.div
          key={t.num}
          className="relative cursor-default"
          style={{
            width: 64,
            height: 110,
            borderRadius: 10,
            border: t.active
              ? "1px solid rgba(244,114,182,0.5)"
              : "1px solid rgba(63,63,70,0.4)",
            background: "rgba(24,24,27,0.6)",
            boxShadow: t.active
              ? "0 0 20px rgba(244,114,182,0.15)"
              : "none",
            overflow: "hidden",
          }}
          {...fadeInUp(0.4 + i * 0.1)}
        >
          {/* Inner screen */}
          <div
            className="absolute flex flex-col"
            style={{
              inset: 3,
              borderRadius: 7,
              overflow: "hidden",
              background: "linear-gradient(180deg, #1c1c20, #18181b)",
              padding: "14px 4px 4px",
            }}
          >
            <div className="h-2 rounded bg-zinc-700/30 mb-1" />
            <div
              className="text-center my-1.5"
              style={{
                fontSize: 8,
                fontWeight: 600,
                color: t.active ? "#f472b6" : "#71717a",
              }}
            >
              {t.value}
            </div>
            <div
              className="w-[60%] mx-auto rounded"
              style={{
                height: 10,
                background: "rgba(139,92,246,0.2)",
              }}
            />
          </div>

          {/* Frame number */}
          <div
            className="absolute bottom-1 right-1.5 font-semibold"
            style={{
              fontSize: 7,
              color: t.active ? "#f472b6" : "#52525b",
            }}
          >
            #{t.num}
          </div>
        </motion.div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// CLI panel
// ---------------------------------------------------------------------------

function CliPanel() {
  return (
    <motion.div
      className="w-full max-w-[400px] mx-auto"
      style={{
        background: "rgba(24,24,27,0.7)",
        border: "1px solid rgba(63,63,70,0.3)",
        borderRadius: 10,
        padding: "14px 16px",
        fontFamily: "'SF Mono','Fira Code',monospace",
        fontSize: 11,
        lineHeight: 1.8,
      }}
      {...fadeInUp(0.9)}
    >
      <div className="text-zinc-700">$ Agent's verification loop</div>
      <div>
        <span className="text-zinc-400">remo call</span>{" "}
        <span className="text-emerald-400">counter.increment</span>{" "}
        <span className="text-amber-400">{"'{\"amount\": 1}'"}</span>
      </div>
      <div>
        <span className="text-zinc-400">remo</span>{" "}
        <span className="text-emerald-400">screenshot</span>{" "}
        <span className="text-amber-400">--format jpeg</span>
      </div>
      <div>
        <span className="text-emerald-400">✓</span>{" "}
        <span className="text-pink-400">Δ detected</span>{" "}
        <span className="text-zinc-700">— counter 3→4, UI verified</span>
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// ScreenshotSection
// ---------------------------------------------------------------------------

export function ScreenshotSection() {
  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(244,114,182,0.07)"
        secondary="rgba(251,146,60,0.05)"
        primaryPos="50% 30%"
        secondaryPos="35% 65%"
      />
      <FloatingParticles
        particles={[
          { top: "18%", left: "20%", color: "#f472b6", duration: 6, delay: 0 },
          { top: "60%", left: "78%", color: "#f472b6", duration: 8, delay: 2 },
          { top: "82%", left: "30%", color: "#fbbf24", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="Screenshot Capture"
        labelColor="#f472b6"
        title="Instant visual verification"
        subtitle="Capture the screen after every action. Agents verify UI state autonomously — no manual checking, no guesswork."
      />

      <div className="relative z-10 flex flex-col items-center gap-6 w-full">
        {/* Phone */}
        <motion.div {...fadeInUp(0.2)}>
          <ShutterPhone />
        </motion.div>

        {/* Thumbnails */}
        <ThumbnailStrip />

        {/* CLI */}
        <CliPanel />
      </div>
    </ShowcaseSection>
  );
}
