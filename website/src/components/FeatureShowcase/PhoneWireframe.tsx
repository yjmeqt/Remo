import { motion } from "framer-motion";

// UI element IDs used for bidirectional hover linking with JSON panel
export type ElementId =
  | "window"
  | "nav"
  | "content"
  | "text"
  | "button"
  | "list"
  | "list-1"
  | "list-2"
  | "list-3"
  | "tab";

interface PhoneWireframeProps {
  hoveredId: ElementId | null;
  onHover: (id: ElementId | null) => void;
}

function UiElement({
  id,
  hoveredId,
  onHover,
  label,
  className,
  children,
}: {
  id: ElementId;
  hoveredId: ElementId | null;
  onHover: (id: ElementId | null) => void;
  label: string;
  className?: string;
  children?: React.ReactNode;
}) {
  const isHovered = hoveredId === id;

  return (
    <div
      className={`relative flex items-center justify-center rounded-lg text-[10px] font-medium tracking-wide transition-all duration-300 cursor-default ${className ?? ""}`}
      style={{
        border: `1px dashed rgba(139,92,246,${isHovered ? 0.6 : 0.25})`,
        color: `rgba(139,92,246,${isHovered ? 0.9 : 0.5})`,
        background: `rgba(139,92,246,${isHovered ? 0.08 : 0.04})`,
        boxShadow: isHovered
          ? "0 0 20px rgba(139,92,246,0.15), inset 0 0 20px rgba(139,92,246,0.05)"
          : "none",
      }}
      onMouseEnter={() => onHover(id)}
      onMouseLeave={() => onHover(null)}
    >
      {children ?? label}
    </div>
  );
}

export function PhoneWireframe({ hoveredId, onHover }: PhoneWireframeProps) {
  return (
    <div
      className="relative flex flex-col gap-1.5 flex-shrink-0"
      style={{
        width: 220,
        height: 440,
        borderRadius: 36,
        border: "1.5px solid rgba(63,63,70,0.6)",
        padding: "16px 12px",
        background: "rgba(24,24,27,0.4)",
        backdropFilter: "blur(20px)",
        boxShadow:
          "0 0 0 1px rgba(255,255,255,0.03), 0 20px 60px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.05)",
      }}
    >
      {/* Notch */}
      <div
        className="absolute top-2 left-1/2 -translate-x-1/2 rounded-[10px]"
        style={{
          width: 60,
          height: 20,
          background: "rgba(9,9,11,0.8)",
          border: "1px solid rgba(63,63,70,0.4)",
        }}
      />

      {/* Scan line */}
      <motion.div
        className="absolute left-0 right-0 h-[2px] pointer-events-none"
        style={{
          background:
            "linear-gradient(90deg, transparent 0%, #8b5cf6 30%, #c084fc 50%, #8b5cf6 70%, transparent 100%)",
          boxShadow:
            "0 0 20px rgba(139,92,246,0.6), 0 0 60px rgba(139,92,246,0.3)",
        }}
        animate={{ top: ["5%", "95%"], opacity: [0, 0.8, 0.8, 0] }}
        transition={{
          duration: 3,
          ease: "easeInOut",
          repeat: Infinity,
          times: [0, 0.1, 0.9, 1],
        }}
      />

      {/* NavigationBar */}
      <UiElement
        id="nav"
        hoveredId={hoveredId}
        onHover={onHover}
        label="NavigationBar"
        className="h-[42px] mt-5"
      />

      {/* ContentView */}
      <UiElement
        id="content"
        hoveredId={hoveredId}
        onHover={onHover}
        label="ContentView"
        className="h-[160px] flex-col gap-1"
      >
        <span className="text-[10px]" style={{ color: "inherit" }}>
          ContentView
        </span>
        <div className="flex flex-col gap-1 w-[80%]">
          <div
            className="h-[22px] rounded flex items-center justify-center text-[8px] cursor-default transition-all duration-300"
            style={{
              border: `1px dashed rgba(167,139,250,${hoveredId === "text" ? 0.5 : 0.2})`,
              color: `rgba(167,139,250,${hoveredId === "text" ? 0.8 : 0.4})`,
              background: `rgba(167,139,250,${hoveredId === "text" ? 0.06 : 0})`,
            }}
            onMouseEnter={() => onHover("text")}
            onMouseLeave={() => onHover(null)}
          >
            Text "Counter: 3"
          </div>
          <div
            className="h-[22px] rounded flex items-center justify-center text-[8px] cursor-default transition-all duration-300"
            style={{
              border: `1px dashed rgba(167,139,250,${hoveredId === "button" ? 0.5 : 0.2})`,
              color: `rgba(167,139,250,${hoveredId === "button" ? 0.8 : 0.4})`,
              background: `rgba(167,139,250,${hoveredId === "button" ? 0.06 : 0})`,
            }}
            onMouseEnter={() => onHover("button")}
            onMouseLeave={() => onHover(null)}
          >
            Button "Increment"
          </div>
        </div>
      </UiElement>

      {/* List */}
      <UiElement
        id="list"
        hoveredId={hoveredId}
        onHover={onHover}
        label=""
        className="h-[100px] flex-col gap-0.5"
      >
        {(["list-1", "list-2", "list-3"] as const).map((id, i) => (
          <div
            key={id}
            className="w-[90%] h-[24px] rounded flex items-center pl-2 text-[8px] cursor-default transition-all duration-300"
            style={{
              border: `1px dashed rgba(167,139,250,${hoveredId === id ? 0.5 : 0.15})`,
              color: `rgba(167,139,250,${hoveredId === id ? 0.7 : 0.3})`,
            }}
            onMouseEnter={() => onHover(id)}
            onMouseLeave={() => onHover(null)}
          >
            ▸ Item {i + 1}
          </div>
        ))}
      </UiElement>

      {/* TabBar */}
      <UiElement
        id="tab"
        hoveredId={hoveredId}
        onHover={onHover}
        label="TabBar"
        className="h-[44px]"
      />
    </div>
  );
}
