import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import type { DemoStep } from "./timeline";

interface AgentTerminalProps {
  visibleSteps: DemoStep[];
  isResetting: boolean;
}

function TerminalLine({ step }: { step: DemoStep }) {
  const { type, text } = step.terminal;

  const colorClass = {
    prompt: "text-zinc-300",
    claude: "text-zinc-500",
    command: "text-zinc-300",
    result: "text-emerald-400",
  }[type];

  const isCommand = type === "command";
  const isClaude = type === "claude";

  return (
    <motion.div
      initial={{ opacity: 0, y: 4 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3 }}
      className={cn(
        isCommand &&
          "bg-[#09090b] border border-zinc-800 rounded-md px-2 py-1.5 my-1",
        !isCommand && "my-0.5"
      )}
    >
      {isClaude && (
        <span className="text-violet-400 mr-1.5">Claude</span>
      )}
      <span className={colorClass}>{text}</span>
    </motion.div>
  );
}

export function AgentTerminal({
  visibleSteps,
  isResetting,
}: AgentTerminalProps) {
  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-xl overflow-hidden min-h-full flex flex-col">
      {/* Title bar */}
      <div className="flex items-center gap-1.5 px-3 py-2 bg-zinc-900/80 border-b border-zinc-800">
        <span className="w-2.5 h-2.5 rounded-full bg-red-500" />
        <span className="w-2.5 h-2.5 rounded-full bg-yellow-500" />
        <span className="w-2.5 h-2.5 rounded-full bg-green-500" />
        <span className="text-[11px] text-zinc-500 ml-2">Claude Code</span>
      </div>

      {/* Terminal content */}
      <div className="flex-1 p-4 font-mono text-[11px] leading-relaxed overflow-y-auto">
        <motion.div
          animate={{ opacity: isResetting ? 0 : 1 }}
          transition={{ duration: 0.5 }}
        >
          {visibleSteps.map((step, i) => (
            <TerminalLine key={`${step.time}-${i}`} step={step} />
          ))}
        </motion.div>
        {!isResetting && (
          <div className="text-zinc-600 mt-1">
            █ <span className="animate-pulse">_</span>
          </div>
        )}
      </div>
    </div>
  );
}
