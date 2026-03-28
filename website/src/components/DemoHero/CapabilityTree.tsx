import { motion } from "framer-motion";
import { cn } from "@/lib/utils";

interface CapabilityTreeProps {
  activeHighlight: string | null;
}

interface TreeNode {
  id: string;
  label: string;
  children?: TreeNode[];
}

const TREE: TreeNode[] = [
  {
    id: "device",
    label: "device",
    children: [
      { id: "device.screenshot", label: "screenshot" },
      { id: "device.video_start", label: "video_start" },
      { id: "device.video_stop", label: "video_stop" },
      { id: "device.view_tree", label: "view_tree" },
    ],
  },
  {
    id: "counter",
    label: "counter",
    children: [
      { id: "counter.increment", label: "increment" },
      { id: "counter.decrement", label: "decrement" },
      { id: "counter.get_count", label: "get_count" },
    ],
  },
  {
    id: "items",
    label: "items",
    children: [
      { id: "items.add_item", label: "add_item" },
      { id: "items.delete_item", label: "delete_item" },
      { id: "items.list_items", label: "list_items" },
    ],
  },
  {
    id: "settings",
    label: "settings",
    children: [
      { id: "settings.toggle_flag", label: "toggle_flag" },
      { id: "settings.reset", label: "reset" },
    ],
  },
];

function TreeLeaf({
  node,
  isLast,
  activeHighlight,
}: {
  node: TreeNode;
  isLast: boolean;
  activeHighlight: string | null;
}) {
  const isActive = activeHighlight === node.id;
  const prefix = isLast ? "└─" : "├─";

  return (
    <div className="flex items-center">
      <span className="text-zinc-600">{prefix} </span>
      <motion.span
        className={cn(
          "px-1 rounded",
          isActive ? "text-emerald-400 bg-emerald-400/10" : "text-zinc-300"
        )}
        animate={
          isActive
            ? {
                boxShadow: [
                  "0 0 0px rgba(52,211,153,0)",
                  "0 0 12px rgba(52,211,153,0.3)",
                  "0 0 0px rgba(52,211,153,0)",
                ],
              }
            : { boxShadow: "0 0 0px rgba(52,211,153,0)" }
        }
        transition={{ duration: 1.2, repeat: isActive ? Infinity : 0 }}
      >
        {node.label}
      </motion.span>
      {isActive && (
        <motion.span
          className="text-amber-400 text-[10px] ml-2"
          initial={{ opacity: 0, x: -4 }}
          animate={{ opacity: 1, x: 0 }}
        >
          ← active
        </motion.span>
      )}
    </div>
  );
}

function TreeGroup({
  node,
  isLast,
  activeHighlight,
}: {
  node: TreeNode;
  isLast: boolean;
  activeHighlight: string | null;
}) {
  const prefix = isLast ? "└─" : "├─";
  const isGroupActive =
    activeHighlight !== null && activeHighlight.startsWith(node.id);

  return (
    <div>
      <div className="flex items-center">
        <span className="text-zinc-600">{prefix} </span>
        <span
          className={cn(
            "font-medium",
            isGroupActive ? "text-zinc-50" : "text-zinc-300"
          )}
        >
          {node.label}
        </span>
      </div>
      {node.children && (
        <div className="pl-4">
          {node.children.map((child, i) => (
            <TreeLeaf
              key={child.id}
              node={child}
              isLast={i === node.children!.length - 1}
              activeHighlight={activeHighlight}
            />
          ))}
        </div>
      )}
    </div>
  );
}

export function CapabilityTree({ activeHighlight }: CapabilityTreeProps) {
  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-4 min-h-full">
      <div className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500 mb-3">
        Capability Tree
      </div>
      <div className="font-mono text-[11px] leading-relaxed">
        <div className="text-violet-400 mb-1">📱 RemoExample</div>
        <div className="pl-3">
          {TREE.map((group, i) => (
            <TreeGroup
              key={group.id}
              node={group}
              isLast={i === TREE.length - 1}
              activeHighlight={activeHighlight}
            />
          ))}
        </div>
      </div>
      <div className="mt-4 pt-3 border-t border-zinc-800 text-[9px] text-zinc-600 text-center">
        Nodes highlight as agent invokes
      </div>
    </div>
  );
}
