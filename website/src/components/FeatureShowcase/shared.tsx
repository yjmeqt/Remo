import { type ReactNode } from "react";
import { motion } from "framer-motion";

// ---------------------------------------------------------------------------
// Animation constants
// ---------------------------------------------------------------------------

const EASE = [0.25, 0.4, 0.25, 1] as const;

export const fadeInUp = (delay = 0) => ({
  initial: { opacity: 0, y: 30 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, amount: 0.3 },
  transition: { duration: 0.7, delay, ease: EASE },
});

export const fadeInLeft = (delay = 0) => ({
  initial: { opacity: 0, x: -30 },
  whileInView: { opacity: 1, x: 0 },
  viewport: { once: true, amount: 0.3 },
  transition: { duration: 0.7, delay, ease: EASE },
});

export const fadeInRight = (delay = 0) => ({
  initial: { opacity: 0, x: 30 },
  whileInView: { opacity: 1, x: 0 },
  viewport: { once: true, amount: 0.3 },
  transition: { duration: 0.7, delay, ease: EASE },
});

export const fadeIn = (delay = 0) => ({
  initial: { opacity: 0 },
  whileInView: { opacity: 1 },
  viewport: { once: true, amount: 0.3 },
  transition: { duration: 0.5, delay, ease: EASE },
});

// ---------------------------------------------------------------------------
// ShowcaseSection — full-viewport wrapper
// ---------------------------------------------------------------------------

export function ShowcaseSection({ children }: { children: ReactNode }) {
  return (
    <section className="relative min-h-screen flex flex-col items-center justify-center px-10 py-20 overflow-hidden">
      {children}
    </section>
  );
}

// ---------------------------------------------------------------------------
// SectionHeader — label + gradient title + subtitle
// ---------------------------------------------------------------------------

interface SectionHeaderProps {
  label: string;
  labelColor: string;
  title: string;
  subtitle: string;
}

export function SectionHeader({
  label,
  labelColor,
  title,
  subtitle,
}: SectionHeaderProps) {
  return (
    <motion.div className="text-center mb-16" {...fadeInUp(0)}>
      <p
        className="text-[11px] font-semibold uppercase tracking-[3px] mb-4"
        style={{ color: labelColor }}
      >
        {label}
      </p>
      <h2 className="text-4xl md:text-[48px] font-bold tracking-[-1.5px] leading-[1.1] bg-gradient-to-b from-white to-zinc-400 bg-clip-text text-transparent">
        {title}
      </h2>
      <p className="text-[17px] text-zinc-500 mt-3 max-w-[520px] mx-auto leading-relaxed">
        {subtitle}
      </p>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// GlassPanel — glassmorphism code panel with colored top-edge glow
// ---------------------------------------------------------------------------

interface GlassPanelProps {
  children: ReactNode;
  glowColor: string;
  className?: string;
}

export function GlassPanel({ children, glowColor, className }: GlassPanelProps) {
  return (
    <div
      className={`relative rounded-2xl p-6 md:p-7 font-mono text-[13px] leading-[1.9] overflow-hidden ${className ?? ""}`}
      style={{
        background: "rgba(24,24,27,0.5)",
        backdropFilter: "blur(20px)",
        border: "1px solid rgba(63,63,70,0.4)",
        boxShadow:
          "0 0 0 1px rgba(255,255,255,0.03), 0 16px 48px rgba(0,0,0,0.4)",
      }}
    >
      {/* Top-edge glow */}
      <div
        className="absolute top-[-1px] left-[15%] right-[15%] h-px"
        style={{
          background: `linear-gradient(90deg, transparent, ${glowColor}, transparent)`,
        }}
      />
      {children}
    </div>
  );
}

// ---------------------------------------------------------------------------
// NoiseOverlay — SVG fractalNoise film grain
// ---------------------------------------------------------------------------

const NOISE_SVG =
  "url(\"data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")";

export function NoiseOverlay() {
  return (
    <div
      className="absolute inset-0 pointer-events-none opacity-[0.03]"
      style={{ backgroundImage: NOISE_SVG }}
    />
  );
}

// ---------------------------------------------------------------------------
// AmbientLight — dual radial gradients
// ---------------------------------------------------------------------------

interface AmbientLightProps {
  primary: string;
  secondary: string;
  primaryPos?: string;
  secondaryPos?: string;
}

export function AmbientLight({
  primary,
  secondary,
  primaryPos = "35% 40%",
  secondaryPos = "65% 55%",
}: AmbientLightProps) {
  return (
    <div
      className="absolute inset-0 pointer-events-none"
      style={{
        background: `radial-gradient(ellipse 600px 400px at ${primaryPos}, ${primary} 0%, transparent 100%), radial-gradient(ellipse 500px 300px at ${secondaryPos}, ${secondary} 0%, transparent 100%)`,
      }}
    />
  );
}

// ---------------------------------------------------------------------------
// FloatingParticles — 3 animated dots
// ---------------------------------------------------------------------------

interface ParticleConfig {
  top: string;
  left: string;
  color: string;
  duration: number;
  delay: number;
}

export function FloatingParticles({
  particles,
}: {
  particles: ParticleConfig[];
}) {
  return (
    <>
      {particles.map((p, i) => (
        <motion.div
          key={i}
          className="absolute w-[2px] h-[2px] rounded-full"
          style={{ top: p.top, left: p.left, background: p.color }}
          animate={{
            y: [0, -20, 0],
            scale: [1, 1.5, 1],
            opacity: [0.3, 0.6, 0.3],
          }}
          transition={{
            duration: p.duration,
            delay: p.delay,
            repeat: Infinity,
            ease: "easeInOut",
          }}
        />
      ))}
    </>
  );
}

// ---------------------------------------------------------------------------
// GradientConnector — animated vertical line between panels
// ---------------------------------------------------------------------------

interface GradientConnectorProps {
  fromColor: string;
  toColor: string;
  height?: number;
}

export function GradientConnector({
  fromColor,
  toColor,
  height = 48,
}: GradientConnectorProps) {
  return (
    <div
      className="relative overflow-hidden mx-auto"
      style={{ width: 1.5, height }}
    >
      <div
        className="absolute inset-0 rounded-sm"
        style={{ background: "rgba(63,63,70,0.2)" }}
      />
      <motion.div
        className="absolute left-0 w-full rounded-sm"
        style={{
          height: "60%",
          background: `linear-gradient(180deg, transparent, ${fromColor}, ${toColor}, transparent)`,
        }}
        animate={{ top: ["-60%", "100%"] }}
        transition={{ duration: 2, ease: "easeInOut", repeat: Infinity }}
      />
    </div>
  );
}
