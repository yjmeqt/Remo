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
// Phone with REC badge
// ---------------------------------------------------------------------------

function RecPhone() {
  return (
    <div
      className="relative flex-shrink-0"
      style={{ width: 150, height: 300, borderRadius: 26 }}
    >
      <div
        className="absolute inset-0 overflow-hidden"
        style={{
          borderRadius: 26,
          border: "1.5px solid rgba(63,63,70,0.4)",
          background: "rgba(9,9,11,0.8)",
        }}
      >
        {/* Notch */}
        <div
          className="absolute top-[6px] left-1/2 -translate-x-1/2 z-10"
          style={{
            width: 42,
            height: 14,
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
          {/* REC badge */}
          <div
            className="absolute top-[38px] left-[10px] z-20 flex items-center gap-1"
            style={{
              fontSize: 8,
              textTransform: "uppercase",
              letterSpacing: 1.5,
              fontWeight: 700,
              color: "#ef4444",
              background: "rgba(239,68,68,0.15)",
              border: "1px solid rgba(239,68,68,0.3)",
              padding: "2px 7px",
              borderRadius: 4,
            }}
          >
            <motion.span
              className="rounded-full"
              style={{ width: 4, height: 4, background: "#ef4444" }}
              animate={{ opacity: [0.4, 1, 0.4] }}
              transition={{
                duration: 1.5,
                repeat: Infinity,
                ease: "easeInOut",
              }}
            />
            Rec
          </div>

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

          {/* Animated list rows */}
          <div className="mt-3 flex flex-col gap-1">
            {[0, 0.3, 0.6].map((delay, i) => (
              <motion.div
                key={i}
                className="rounded bg-zinc-700/15"
                style={{
                  height: 12,
                  width: i === 1 ? "85%" : i === 2 ? "70%" : "100%",
                }}
                animate={{ y: [0, -4, 0], opacity: [0.5, 0.8, 0.5] }}
                transition={{
                  duration: 4,
                  delay,
                  repeat: Infinity,
                  ease: "easeInOut",
                }}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Waveform bar heights (fixed, pseudo-random)
// ---------------------------------------------------------------------------

const BAR_HEIGHTS = [
  12, 24, 18, 32, 20, 38, 28, 16, 30, 22, 36, 14, 26, 40, 20, 34, 18, 28,
  10, 22, 30, 16, 36, 24, 32, 12, 38, 20, 26, 14,
];

// ---------------------------------------------------------------------------
// Timeline bar
// ---------------------------------------------------------------------------

function TimelineBar() {
  return (
    <div
      className="w-full max-w-[500px]"
      style={{
        background: "rgba(24,24,27,0.7)",
        border: "1px solid rgba(63,63,70,0.3)",
        borderRadius: 10,
        padding: "16px 20px",
      }}
    >
      {/* Header */}
      <div className="flex justify-between items-center mb-2.5">
        <span
          style={{
            fontSize: 10,
            color: "#38bdf8",
            fontWeight: 600,
            textTransform: "uppercase",
            letterSpacing: 1.5,
          }}
        >
          Recording
        </span>
        <span
          style={{
            fontSize: 10,
            color: "#52525b",
            fontFamily: "'SF Mono','Fira Code',monospace",
          }}
        >
          00:04.2 / 00:06.5
        </span>
      </div>

      {/* Waveform */}
      <div className="flex items-end gap-[1.5px]" style={{ height: 40 }}>
        {BAR_HEIGHTS.map((h, i) => (
          <motion.div
            key={i}
            style={{
              width: 3,
              height: h,
              borderRadius: 1.5,
              background: "rgba(56,189,248,0.4)",
            }}
            animate={{ opacity: [0.3, 0.8, 0.3] }}
            transition={{
              duration: 2,
              delay: (i / BAR_HEIGHTS.length) * 2,
              repeat: Infinity,
              ease: "easeInOut",
            }}
          />
        ))}
      </div>

      {/* Playhead track */}
      <div
        className="relative mt-2"
        style={{
          height: 2,
          background: "rgba(63,63,70,0.3)",
          borderRadius: 1,
        }}
      >
        <div
          className="absolute top-0 left-0 h-full"
          style={{
            width: "65%",
            borderRadius: 1,
            background: "linear-gradient(90deg, #38bdf8, #818cf8)",
          }}
        />
        <div
          className="absolute"
          style={{
            top: -3,
            left: "65%",
            width: 8,
            height: 8,
            borderRadius: "50%",
            background: "#38bdf8",
            border: "2px solid #09090b",
            boxShadow: "0 0 8px rgba(56,189,248,0.4)",
          }}
        />
      </div>

      {/* Frame markers */}
      <div
        className="flex justify-between mt-1.5"
        style={{
          fontSize: 7,
          color: "#27272a",
          fontFamily: "'SF Mono','Fira Code',monospace",
        }}
      >
        <span>0:00</span>
        <span>0:02</span>
        <span>0:04</span>
        <span>0:06</span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// VideoStreamSection
// ---------------------------------------------------------------------------

export function VideoStreamSection() {
  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(56,189,248,0.07)"
        secondary="rgba(129,140,248,0.05)"
        primaryPos="50% 30%"
        secondaryPos="60% 65%"
      />
      <FloatingParticles
        particles={[
          { top: "15%", left: "18%", color: "#38bdf8", duration: 6, delay: 0 },
          { top: "55%", left: "82%", color: "#818cf8", duration: 8, delay: 2 },
          { top: "80%", left: "25%", color: "#38bdf8", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="Live Video Streaming"
        labelColor="#38bdf8"
        title="Stream the screen in real time"
        subtitle="H.264 hardware-encoded mirroring. Record sessions, review animations, verify transitions — frame by frame."
      />

      <div className="relative z-10 flex flex-col items-center gap-6 w-full">
        {/* Phone */}
        <motion.div {...fadeInUp(0.2)}>
          <RecPhone />
        </motion.div>

        {/* Timeline */}
        <motion.div className="w-full flex justify-center" {...fadeInUp(0.5)}>
          <TimelineBar />
        </motion.div>
      </div>
    </ShowcaseSection>
  );
}
