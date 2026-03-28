import { useRef, useEffect } from "react";

interface IPhoneFrameProps {
  videoTime: number;
}

export function IPhoneFrame({ videoTime }: IPhoneFrameProps) {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    if (videoRef.current && videoRef.current.readyState >= 2) {
      videoRef.current.currentTime = videoTime;
    }
  }, [videoTime]);

  return (
    <div className="flex flex-col items-center rounded-2xl bg-[#0f0f11] border border-zinc-800/50 p-8">
      <div className="relative w-[200px] bg-zinc-800 border-[3px] border-zinc-700 rounded-[32px] p-3 shadow-[0_4px_40px_rgba(0,0,0,0.5),0_0_0_1px_rgba(255,255,255,0.03)]">
        {/* Dynamic Island */}
        <div className="w-[60px] h-[12px] bg-black rounded-lg mx-auto mb-2" />

        {/* Screen */}
        <div className="bg-black rounded-[20px] aspect-[9/19.5] overflow-hidden flex items-center justify-center">
          <video
            ref={videoRef}
            className="w-full h-full object-cover hidden"
            src="/demo.mp4"
            muted
            playsInline
          />
          <div className="flex flex-col items-center justify-center w-full h-full bg-gradient-to-b from-zinc-900 to-black">
            <div className="text-4xl font-bold text-emerald-400">3</div>
            <div className="text-[10px] text-zinc-500 mt-1">RemoExample</div>
            <div className="flex gap-2 mt-3">
              <span className="bg-zinc-800 text-zinc-300 px-3 py-1 rounded text-[10px]">−</span>
              <span className="bg-zinc-800 text-zinc-300 px-3 py-1 rounded text-[10px]">+</span>
            </div>
          </div>
        </div>

        {/* Home indicator */}
        <div className="w-[60px] h-[4px] bg-zinc-700 rounded-full mx-auto mt-2" />
      </div>
      <div className="text-[10px] text-zinc-600 mt-3">▶ Synced app video</div>
    </div>
  );
}
