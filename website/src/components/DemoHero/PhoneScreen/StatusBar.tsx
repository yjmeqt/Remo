export function StatusBar() {
  return (
    <div className="relative z-10 flex items-center justify-between px-6 pt-1.5 pb-1 text-[11px] font-semibold text-zinc-900">
      <span>9:41</span>
      <div className="flex items-center gap-1">
        <SignalBars />
        <WifiIcon />
        <BatteryIcon />
      </div>
    </div>
  );
}

function SignalBars() {
  return (
    <div className="flex items-end gap-[1.5px] h-2.5">
      {[3, 5, 7, 9].map((h) => (
        <span
          key={h}
          className="w-[2px] rounded-[1px] bg-zinc-900"
          style={{ height: `${h}px` }}
        />
      ))}
    </div>
  );
}

function WifiIcon() {
  return (
    <svg width="13" height="9" viewBox="0 0 13 9" fill="none">
      <path
        d="M6.5 8.5l1.6-1.6a2.3 2.3 0 0 0-3.2 0L6.5 8.5Z"
        fill="currentColor"
      />
      <path
        d="M3.4 5.4a4.5 4.5 0 0 1 6.2 0l-1.1 1.1a3 3 0 0 0-4 0L3.4 5.4Z"
        fill="currentColor"
      />
      <path
        d="M.9 2.9a8.2 8.2 0 0 1 11.2 0L11 4.0a6.6 6.6 0 0 0-9 0L.9 2.9Z"
        fill="currentColor"
      />
    </svg>
  );
}

function BatteryIcon() {
  return (
    <div className="flex items-center">
      <div className="relative w-[22px] h-[10px] rounded-[3px] border border-zinc-900/80">
        <span className="absolute left-[1px] top-[1px] bottom-[1px] w-[16px] rounded-[1.5px] bg-zinc-900" />
      </div>
      <span className="ml-[1px] w-[1px] h-[4px] rounded-[1px] bg-zinc-900/80" />
    </div>
  );
}
