import { CapabilitySection } from "./CapabilitySection";
import { ViewTreeSection } from "./ViewTreeSection";
import { ScreenshotSection } from "./ScreenshotSection";
import { VideoStreamSection } from "./VideoStreamSection";
import { DeviceDiscoverySection } from "./DeviceDiscoverySection";
import { DynamicRegistrationSection } from "./DynamicRegistrationSection";

export function FeatureShowcase() {
  return (
    <>
      <CapabilitySection />
      <ViewTreeSection />
      <ScreenshotSection />
      <VideoStreamSection />
      <DeviceDiscoverySection />
      <DynamicRegistrationSection />
    </>
  );
}
