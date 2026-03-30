import { useRef, useEffect } from "react";

interface IPhoneFrameProps {
  videoTime: number;
}

export function IPhoneFrame({ videoTime }: IPhoneFrameProps) {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    if (videoRef.current && videoRef.current.readyState >= 2) {
      videoRef.current.currentTime = Math.max(0, videoTime);
    }
  }, [videoTime]);

  const showVideo = videoTime >= 0;
  const fallbackSrc = `${import.meta.env.BASE_URL}iphone-lock-screen.png`;

  return (
    <div className="flex flex-col items-center">
      {/* iPhone frame — 300px wide, ~613px tall (aspect 450/920) */}
      <div
        className="relative w-[300px]"
        style={{ aspectRatio: "450/920" }}
      >
        {/* Screen content sits behind the frame bezel */}
        <div className="absolute left-[5.3%] right-[5.3%] top-[2.5%] bottom-[2.5%] rounded-[32px] overflow-hidden bg-black">
          <img
            src={fallbackSrc}
            alt="Demo phone idle screen"
            className="absolute inset-0 w-full h-full object-cover"
            draggable={false}
            style={{ opacity: showVideo ? 0 : 1 }}
          />

          <video
            ref={videoRef}
            data-testid="demo-phone-video"
            className="absolute inset-0 w-full h-full object-cover"
            src={`${import.meta.env.BASE_URL}demo.mp4`}
            muted
            playsInline
            style={{ opacity: showVideo ? 1 : 0 }}
          />
        </div>

        {/* Figma iPhone 17 Pro frame overlay */}
        <img
          src={`${import.meta.env.BASE_URL}iphone-frame.png`}
          alt=""
          className="absolute inset-0 w-full h-full pointer-events-none"
          draggable={false}
        />
      </div>
    </div>
  );
}
