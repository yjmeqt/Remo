import { PhoneFrame } from "../PhoneFrame";
import { PhoneScreen } from "./PhoneScreen/PhoneScreen";
import type { PhoneState } from "./useTimeline";

interface IPhoneFrameProps {
  phoneState: PhoneState;
}

export function IPhoneFrame({ phoneState }: IPhoneFrameProps) {
  const fallbackSrc = `${import.meta.env.BASE_URL}iphone-lock-screen.png`;

  return (
    <div className="flex flex-col items-center">
      <PhoneFrame width={300}>
        <img
          src={fallbackSrc}
          alt="Demo phone idle screen"
          className="absolute inset-0 w-full h-full object-cover"
          draggable={false}
          style={{ opacity: phoneState.isOn ? 0 : 1 }}
        />

        <div
          data-testid="demo-phone-screen"
          className="absolute inset-0 transition-opacity duration-300"
          style={{ opacity: phoneState.isOn ? 1 : 0 }}
        >
          <PhoneScreen state={phoneState} />
        </div>
      </PhoneFrame>
    </div>
  );
}
