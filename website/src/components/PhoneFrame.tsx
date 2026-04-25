import type { CSSProperties, ReactNode } from "react";

interface PhoneFrameProps {
  width: number;
  children: ReactNode;
  className?: string;
  /** Background color for the screen area when children don't fill it. */
  screenBackground?: string;
  style?: CSSProperties;
}

const FRAME_ASPECT = "450/920";
const SCREEN_INSET_X = 5.3; // %
const SCREEN_INSET_Y = 2.5; // %
const SCREEN_RADIUS_RATIO = 32 / 300; // hero is 300px wide with 32px screen radius

/** iPhone bezel + screen container shared across hero and feature sections. */
export function PhoneFrame({
  width,
  children,
  className = "",
  screenBackground = "#000",
  style,
}: PhoneFrameProps) {
  const screenRadius = Math.round(width * SCREEN_RADIUS_RATIO);

  return (
    <div
      className={`relative flex-shrink-0 ${className}`}
      style={{ width, aspectRatio: FRAME_ASPECT, ...style }}
    >
      <div
        className="absolute overflow-hidden"
        style={{
          left: `${SCREEN_INSET_X}%`,
          right: `${SCREEN_INSET_X}%`,
          top: `${SCREEN_INSET_Y}%`,
          bottom: `${SCREEN_INSET_Y}%`,
          borderRadius: screenRadius,
          background: screenBackground,
        }}
      >
        {children}
      </div>

      <img
        src={`${import.meta.env.BASE_URL}iphone-frame.png`}
        alt=""
        className="absolute inset-0 w-full h-full pointer-events-none select-none"
        draggable={false}
      />
    </div>
  );
}
