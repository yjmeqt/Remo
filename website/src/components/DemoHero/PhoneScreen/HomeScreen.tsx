import { motion } from "framer-motion";
import { LIQUID_GLASS } from "./colors";

interface HomeScreenProps {
  accent: string;
}

export function HomeScreen({ accent }: HomeScreenProps) {
  return (
    <div className="absolute inset-0 flex flex-col px-5 pt-9 pb-2 bg-[#f2f2f7]">
      <div
        className={`self-center flex items-center gap-1.5 px-3 py-1.5 rounded-full text-[10px] font-medium text-zinc-500 ${LIQUID_GLASS}`}
      >
        <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
        Remo on port 8421
      </div>

      <div className="text-[10px] text-zinc-500 mt-3 mb-1 px-1">Remo</div>

      <div className="flex-1 flex flex-col items-center justify-center -mt-6">
        <div className="text-[15px] font-medium text-zinc-900 mb-2">
          Hello, Guest!
        </div>
        <motion.div
          key="counter"
          className="text-[56px] font-bold text-zinc-900 leading-none tracking-tight tabular-nums"
        >
          0
        </motion.div>
        <div className="text-[10px] uppercase tracking-[0.15em] text-zinc-500 mt-2">
          Counter
        </div>

        <div className="flex gap-3 mt-6">
          <CounterButton label="−" tint="#ff453a" />
          <CounterButton label="+" tint={accent} />
          <CounterButton label="Reset" tint="#8e8e93" muted />
        </div>
      </div>
    </div>
  );
}

function CounterButton({
  label,
  tint,
  muted,
}: {
  label: string;
  tint: string;
  muted?: boolean;
}) {
  return (
    <div
      className="min-w-[56px] h-[36px] rounded-[10px] flex items-center justify-center text-[14px] font-semibold"
      style={{
        color: tint,
        backgroundColor: muted ? "rgba(120,120,128,0.14)" : `${tint}24`,
      }}
    >
      {label}
    </div>
  );
}
