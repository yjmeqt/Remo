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
    <div className="flex flex-col items-center">
      {/* iPhone frame from Figma — image overlays the screen content */}
      <div className="relative w-[225px]" style={{ aspectRatio: "450/920" }}>
        {/* Screen content sits behind the frame bezel */}
        <div className="absolute left-[5.3%] right-[5.3%] top-[2.5%] bottom-[2.5%] rounded-[24px] overflow-hidden bg-black">
          <video
            ref={videoRef}
            className="w-full h-full object-cover hidden"
            src="/demo.mp4"
            muted
            playsInline
          />
          {/* Placeholder content shown until real video is available */}
          <div className="flex flex-col items-center justify-center w-full h-full bg-gradient-to-b from-zinc-900 to-black">
            <div className="text-4xl font-bold text-emerald-400">3</div>
            <div className="text-[10px] text-zinc-500 mt-1">RemoExample</div>
            <div className="flex gap-2 mt-3">
              <span className="bg-zinc-800 text-zinc-300 px-3 py-1 rounded text-[10px]">
                −
              </span>
              <span className="bg-zinc-800 text-zinc-300 px-3 py-1 rounded text-[10px]">
                +
              </span>
            </div>
          </div>
        </div>

        {/* Figma iPhone 17 Pro frame overlay */}
        <img
          src="/iphone-frame.png"
          alt=""
          className="absolute inset-0 w-full h-full pointer-events-none"
          draggable={false}
        />
      </div>
      <div className="text-[10px] text-zinc-600 mt-3">▶ Synced app video</div>
    </div>
  );
}
