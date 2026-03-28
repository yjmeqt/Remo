import { motion } from "framer-motion";
import {
  ShowcaseSection,
  SectionHeader,
  GlassPanel,
  NoiseOverlay,
  AmbientLight,
  FloatingParticles,
  GradientConnector,
  fadeInUp,
  fadeIn,
} from "./shared";

// ---------------------------------------------------------------------------
// StatusChip — colored dot + label
// ---------------------------------------------------------------------------

function StatusChip({
  label,
  color,
  bgColor,
  borderColor,
  delay,
}: {
  label: string;
  color: string;
  bgColor: string;
  borderColor: string;
  delay: number;
}) {
  return (
    <div
      className="inline-flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-[1.5px] px-2.5 py-1 rounded-md mb-4"
      style={{
        fontFamily: "inherit",
        color,
        background: bgColor,
        border: `1px solid ${borderColor}`,
      }}
    >
      <motion.span
        className="w-[5px] h-[5px] rounded-full"
        style={{ background: color }}
        animate={{ scale: [1, 1.4, 1], opacity: [0.5, 1, 0.5] }}
        transition={{
          duration: 2,
          delay,
          repeat: Infinity,
          ease: "easeInOut",
        }}
      />
      {label}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Code content helpers
// ---------------------------------------------------------------------------

const kw = "text-violet-400";
const fn = "text-emerald-400";
const str = "text-amber-400";
const comment = "text-zinc-700";
const plain = "text-zinc-400";
const result = "text-emerald-400";

function RegisterCode() {
  return (
    <div style={{ fontFamily: "'SF Mono','Fira Code',monospace" }}>
      <div className={comment}>
        {"// Your iOS app — one line to expose a capability"}
      </div>
      <div>
        <span className={kw}>Remo</span>
        {"."}<span className={fn}>register</span>
        {"("}<span className={str}>"counter.increment"</span>
        {") { params "}
        <span className={kw}>in</span>
      </div>
      <div className="pl-4">
        <span className={plain}>counter</span>
        {" += params["}
        <span className={str}>"amount"</span>
        {"] "}
        <span className={kw}>as?</span>
        {" "}<span className={plain}>Int</span>
        {" ?? "}<span className={plain}>1</span>
      </div>
      <div className="pl-4">
        <span className={kw}>return</span>
        {" ["}
        <span className={str}>"count"</span>
        {": "}
        <span className={plain}>counter</span>
        {"]"}
      </div>
      <div>{"}"}</div>
    </div>
  );
}

function InvokeCode() {
  return (
    <div style={{ fontFamily: "'SF Mono','Fira Code',monospace" }}>
      <div className={comment}>$ Agent calls via CLI or JSON-RPC</div>
      <div>
        <span className={plain}>remo call</span>{" "}
        <span className={fn}>counter.increment</span>{" "}
        <span className={str}>{"'{\"amount\": 1}'"}</span>
      </div>
    </div>
  );
}

function ResponseCode() {
  return (
    <div style={{ fontFamily: "'SF Mono','Fira Code',monospace" }}>
      <span className={result}>✓</span>{" "}
      <span className={plain}>{"{"}</span>{" "}
      <span className={str}>"count"</span>
      {": "}
      <span className={plain}>4</span>{" "}
      <span className={plain}>{"}"}</span>
      <span className={`${comment} ml-4`}>← 3ms round-trip</span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// CapabilitySection
// ---------------------------------------------------------------------------

export function CapabilitySection() {
  return (
    <ShowcaseSection>
      <NoiseOverlay />
      <AmbientLight
        primary="rgba(52,211,153,0.07)"
        secondary="rgba(139,92,246,0.05)"
        primaryPos="50% 35%"
        secondaryPos="30% 65%"
      />
      <FloatingParticles
        particles={[
          { top: "15%", left: "12%", color: "#34d399", duration: 6, delay: 0 },
          { top: "55%", left: "85%", color: "#8b5cf6", duration: 8, delay: 2 },
          { top: "85%", left: "20%", color: "#fbbf24", duration: 7, delay: 4 },
        ]}
      />

      <SectionHeader
        label="Capability Invocation"
        labelColor="#34d399"
        title="Register in Swift. Call from anywhere."
        subtitle="Define named handlers in your app. Agents discover and invoke them at runtime — structured input, structured output."
      />

      {/* Pipeline */}
      <div className="relative z-10 flex flex-col items-center w-full max-w-[580px]">
        {/* Register */}
        <motion.div className="w-full" {...fadeInUp(0.2)}>
          <GlassPanel glowColor="rgba(139,92,246,0.5)">
            <StatusChip
              label="Register"
              color="#c084fc"
              bgColor="rgba(139,92,246,0.1)"
              borderColor="rgba(139,92,246,0.2)"
              delay={0}
            />
            <RegisterCode />
          </GlassPanel>
        </motion.div>

        {/* Connector 1 */}
        <motion.div {...fadeIn(0.5)}>
          <GradientConnector fromColor="#8b5cf6" toColor="#34d399" />
        </motion.div>

        {/* Invoke */}
        <motion.div className="w-full" {...fadeInUp(0.6)}>
          <GlassPanel glowColor="rgba(52,211,153,0.5)">
            <StatusChip
              label="Invoke"
              color="#34d399"
              bgColor="rgba(52,211,153,0.1)"
              borderColor="rgba(52,211,153,0.2)"
              delay={0.6}
            />
            <InvokeCode />
          </GlassPanel>
        </motion.div>

        {/* Connector 2 */}
        <motion.div {...fadeIn(0.9)}>
          <GradientConnector fromColor="#34d399" toColor="#fbbf24" />
        </motion.div>

        {/* Response */}
        <motion.div className="w-full" {...fadeInUp(1.0)}>
          <GlassPanel glowColor="rgba(251,191,36,0.4)">
            <StatusChip
              label="Response"
              color="#fbbf24"
              bgColor="rgba(251,191,36,0.1)"
              borderColor="rgba(251,191,36,0.2)"
              delay={1.2}
            />
            <ResponseCode />
          </GlassPanel>
        </motion.div>
      </div>
    </ShowcaseSection>
  );
}
