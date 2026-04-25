import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";

interface ConfettiProps {
  active: boolean;
  /** Bumped each trigger so React re-mounts the particles. */
  triggerKey: number;
}

const COLORS = ["#ff453a", "#0a84ff", "#30d158", "#ffd60a", "#bf5af2", "#ff9f0a", "#ff375f"];
const PARTICLE_COUNT = 60;

interface Particle {
  id: number;
  x: number;
  size: number;
  color: string;
  delay: number;
  duration: number;
  drift: number;
}

function makeParticles(): Particle[] {
  return Array.from({ length: PARTICLE_COUNT }).map((_, i) => ({
    id: i,
    x: Math.random() * 100,
    size: 5 + Math.random() * 6,
    color: COLORS[i % COLORS.length],
    delay: Math.random() * 0.4,
    duration: 1.5 + Math.random() * 0.8,
    drift: -25 + Math.random() * 50,
  }));
}

export function Confetti({ active, triggerKey }: ConfettiProps) {
  return (
    <AnimatePresence>
      {active && <ConfettiBurst key={triggerKey} />}
    </AnimatePresence>
  );
}

function ConfettiBurst() {
  const [particles] = useState(makeParticles);

  return (
    <div className="absolute inset-0 pointer-events-none z-20 overflow-hidden">
      {particles.map((p) => (
        <motion.span
          key={p.id}
          initial={{ x: `${p.x}%`, y: -20, opacity: 1 }}
          animate={{
            x: `calc(${p.x}% + ${p.drift}px)`,
            y: "110%",
            opacity: 0,
          }}
          transition={{
            duration: p.duration,
            delay: p.delay,
            ease: "easeOut",
          }}
          exit={{ opacity: 0 }}
          className="absolute rounded-full"
          style={{
            width: p.size,
            height: p.size,
            backgroundColor: p.color,
            top: 0,
            left: 0,
          }}
        />
      ))}
    </div>
  );
}
