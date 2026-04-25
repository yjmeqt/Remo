import type { ReactNode } from "react";
import { LIQUID_GLASS } from "./colors";
import type { PhoneRoute } from "../timeline";

interface TabBarProps {
  route: PhoneRoute;
  accent: string;
}

const TABS: Array<{ id: PhoneRoute; label: string; icon: () => ReactNode }> = [
  { id: "home", label: "Home", icon: HomeIcon },
  { id: "uikit", label: "Grid", icon: GridIcon },
  { id: "activity", label: "Activity", icon: WaveformIcon },
  { id: "settings", label: "Settings", icon: GearIcon },
];

export function TabBar({ route, accent }: TabBarProps) {
  return (
    <div
      className={`absolute bottom-0 left-0 right-0 ${LIQUID_GLASS} border-t border-black/5 px-2 pt-1.5 pb-3`}
    >
      <div className="flex justify-around">
        {TABS.map((tab) => {
          const Icon = tab.icon;
          const active = tab.id === route;
          return (
            <div
              key={tab.id}
              className="flex flex-col items-center gap-0.5 px-2"
              style={{ color: active ? accent : "#8e8e93" }}
            >
              <div className="h-[18px] flex items-center">
                <Icon />
              </div>
              <span className="text-[9px] font-medium leading-none">
                {tab.label}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function HomeIcon() {
  return (
    <svg width="20" height="18" viewBox="0 0 20 18" fill="none">
      <path
        d="M10 1.2 1.5 8.5h2v8h13v-8h2L10 1.2Z"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function GridIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
      <rect x="1" y="1" width="6.5" height="6.5" rx="1.5" stroke="currentColor" strokeWidth="1.5" />
      <rect x="10.5" y="1" width="6.5" height="6.5" rx="1.5" stroke="currentColor" strokeWidth="1.5" />
      <rect x="1" y="10.5" width="6.5" height="6.5" rx="1.5" stroke="currentColor" strokeWidth="1.5" />
      <rect x="10.5" y="10.5" width="6.5" height="6.5" rx="1.5" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}

function WaveformIcon() {
  return (
    <svg width="20" height="18" viewBox="0 0 20 18" fill="none">
      <path
        d="M2 9h2M5 5v8M8 2v14M11 6v6M14 4v10M17 9h2"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
      />
    </svg>
  );
}

function GearIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
      <circle cx="9" cy="9" r="2.5" stroke="currentColor" strokeWidth="1.5" />
      <path
        d="M9 1.5v2M9 14.5v2M1.5 9h2M14.5 9h2M3.7 3.7l1.4 1.4M12.9 12.9l1.4 1.4M3.7 14.3l1.4-1.4M12.9 5.1l1.4-1.4"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
      />
    </svg>
  );
}
