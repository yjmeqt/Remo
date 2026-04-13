import { CapabilitySection } from "./CapabilitySection";
import { DynamicRegistrationSection } from "./DynamicRegistrationSection";
import { ViewTreeSection } from "./ViewTreeSection";
import { DeviceDiscoverySection } from "./DeviceDiscoverySection";
import { ToolBoundarySection } from "./ToolBoundarySection";

export function FeatureShowcase() {
  return (
    <>
      <CapabilitySection />
      <DynamicRegistrationSection />
      <ViewTreeSection />
      <DeviceDiscoverySection />
      <ToolBoundarySection />
    </>
  );
}
