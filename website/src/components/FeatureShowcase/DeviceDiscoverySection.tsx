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
// Device data
// ---------------------------------------------------------------------------

interface DeviceInfo {
  icon: string;
  name: string;
  os: string;
  connection: "USB" | "Bonjour";
  delay: number;
}

const DEVICES: DeviceInfo[] = [
  { icon: "📱", name: "iPhone 17 Pro", os: "iOS 18.4", connection: "USB", delay: 0 },
  { icon: "📱", name: "iPad Air (M3)", os: "iPadOS 18.4", connection: "USB", delay: 0.5 },
  { icon: "📱", name: "iPhone 16 Sim", os: "iOS 18.0", connection: "Bonjour", delay: 1 },
];

const TAG_STYLES = {
  USB: {
    color: "#fb923c",
    background: "rgba(251,146,60,0.1)",
    border: "1px solid rgba(251,146,60,0.2)",
    dotColor: "#fb923c",
    dotShadow: "0 0 6px rgba(251,146,60,0.5)",
  },
  Bonjour: {
    color: "#a78bfa",
    background: "rgba(167,139,250,0.1)",
    border: "1px solid rgba(167,139,250,0.2)",
    dotColor: "#a78bfa",
    dotShadow: "0 0 6px rgba(167,139,250,0.5)",
  },
};

// ---------------------------------------------------------------------------
// Device card
// ---------------------------------------------------------------------------

function DeviceCard({ device }: { device: DeviceInfo }) {
  const tag = TAG_STYLES[device.connection];

  return (
    <motion.div
      className="relative text-center transition-all duration-300 hover:shadow-[0_0_20px_rgba(251,146,60,0.08)]"
      style={{
        background: "rgba(24,24,27,0.7)",
        border: "1px solid rgba(63,63,70,0.3)",
        borderRadius: 12,
        padding: 16,
      }}
      {...fadeInUp(0.2 + device.delay * 0.3)}
    >
      {/* Status dot */}
      <motion.div
        className="absolute rounded-full"
        style={{
          top: 8,
          right: 8,
          width: 6,
          height: 6,
          background: tag.dotColor,
          boxShadow: tag.dotShadow,
        }}
        animate={{ scale: [1, 1.3, 1], opacity: [0.5, 1, 0.5] }}
        transition={{
          duration: 2,
          delay: device.delay,
          repeat: Infinity,
          ease: "easeInOut",
        }}
      />

      <div className="text-[28px] mb-2">{device.icon}</div>
      <div className="text-[11px] text-zinc-400 font-medium mb-1">
        {device.name}
      </div>
      <div
        className="text-zinc-600"
        style={{
          fontSize: 9,
          fontFamily: "'SF Mono','Fira Code',monospace",
        }}
      >
        {device.os}
      </div>
      <span
        className="inline-block mt-2 font-semibold uppercase"
        style={{
          fontSize: 8,
          letterSpacing: 1,
          padding: "2px 6px",
          borderRadius: 4,
          color: tag.color,
          background: tag.background,
          border: tag.border,
        }}
      >
        {device.connection}
      </span>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// CLI panel
// ---------------------------------------------------------------------------

function CliPanel() {
  return (
    <motion.div
      className="w-full max-w-[480px] mx-auto"
      style={{
        background: "rgba(24,24,27,0.7)",
        border: "1px solid rgba(63,63,70,0.3)",
        borderRadius: 10,
        padding: "14px 16px",
        fontFamily: "'SF Mono','Fira Code',monospace",
        fontSize: 11,
        lineHeight: 1.8,
      }}
      {...fadeInUp(0.7)}
    >
      <div className="text-zinc-700">$ Discover all connected devices</div>
      <div>
        <span className="text-zinc-400">remo</span>{" "}
        <span className="text-emerald-400">devices</span>
      </div>
      <div className="mt-1.5">
        <span className="text-emerald-400">●</span>{" "}
        <span className="text-zinc-400">iPhone 17 Pro</span>{" "}
        <span style={{ color: "#fb923c" }}>USB</span>{" "}
        <span className="text-zinc-700">· iOS 18.4 · 1170×2532</span>
      </div>
      <div>
        <span className="text-emerald-400">●</span>{" "}
        <span className="text-zinc-400">iPad Air (M3)</span>{" "}
        <span style={{ color: "#fb923c" }}>USB</span>{" "}
        <span className="text-zinc-700">· iPadOS 18.4 · 2360×1640</span>
      </div>
      <div>
        <span className="text-emerald-400">●</span>{" "}
        <span className="text-zinc-400">iPhone 16 Sim</span>{" "}
        <span style={{ color: "#a78bfa" }}>Bonjour</span>{" "}
        <span className="text-zinc-700">· iOS 18.0 · 1170×2532</span>
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// DeviceDiscoverySection
// ---------------------------------------------------------------------------

export function DeviceDiscoverySection() {
  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(251,146,60,0.07)"
        secondary="rgba(167,139,250,0.05)"
        primaryPos="50% 35%"
        secondaryPos="35% 60%"
      />
      <FloatingParticles
        particles={[
          { top: "20%", left: "15%", color: "#fb923c", duration: 6, delay: 0 },
          { top: "55%", left: "80%", color: "#a78bfa", duration: 8, delay: 2 },
          { top: "80%", left: "22%", color: "#fb923c", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="Multi-Device Discovery"
        labelColor="#fb923c"
        title="Plug in and go"
        subtitle="USB for physical devices, Bonjour for simulators. Agents find every device automatically — no configuration needed."
      />

      <div className="relative z-10 flex flex-col items-center gap-6 w-full">
        {/* Device grid */}
        <div
          className="grid gap-3 w-full max-w-[480px]"
          style={{ gridTemplateColumns: "repeat(3, 1fr)" }}
        >
          {DEVICES.map((d) => (
            <DeviceCard key={d.name} device={d} />
          ))}
        </div>

        {/* CLI */}
        <CliPanel />
      </div>
    </ShowcaseSection>
  );
}
