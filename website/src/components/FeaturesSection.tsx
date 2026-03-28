import {
  Camera,
  Video,
  TreeDeciduous,
  Zap,
  MonitorSmartphone,
  ToggleRight,
} from "lucide-react";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";

const FEATURES = [
  {
    icon: Camera,
    title: "Screenshot Capture",
    description: "Instant visual verification after any action.",
  },
  {
    icon: Video,
    title: "Live Video Streaming",
    description: "H.264 hardware-encoded screen mirroring.",
  },
  {
    icon: TreeDeciduous,
    title: "View Tree Inspection",
    description: "Full UIView hierarchy as structured JSON.",
  },
  {
    icon: Zap,
    title: "Capability Invocation",
    description: "Register named handlers, agents call them dynamically.",
  },
  {
    icon: MonitorSmartphone,
    title: "Multi-Device Discovery",
    description: "USB + Bonjour, physical devices + simulators.",
  },
  {
    icon: ToggleRight,
    title: "Dynamic Registration",
    description: "Page-level register / unregister lifecycle.",
  },
];

// TODO: replace flat card grid with premium product-style showcase
// Each capability gets a full-width section with:
//   - 3D perspective / parallax demo visual (tilt-on-hover, depth layers)
//   - Scroll-triggered entrance animations (fade + scale + rotate)
//   - Interactive demo: e.g. Screenshot shows a live before/after slider,
//     Video Streaming shows a looping H.264 clip with playback controls,
//     View Tree shows an expandable JSON tree with syntax highlighting,
//     Capability Invocation shows a terminal typing animation with response,
//     Discovery shows an animated device radar/scan visualization,
//     Dynamic Registration shows a timeline of register/unregister lifecycle
//   - Alternating left/right layout (visual | text, text | visual)
//   - Glassmorphism cards with subtle gradient borders
// Reference: Apple product pages, Linear.app features, Vercel homepage
export function FeaturesSection() {
  return (
    <section className="py-20 px-6 border-t border-zinc-800">
      <div className="max-w-5xl mx-auto">
        <h2 className="text-2xl md:text-3xl font-bold tracking-tight text-zinc-50 text-center">
          Core Capabilities
        </h2>
        <p className="text-zinc-500 mt-3 text-center">
          Everything an AI agent needs to interact with iOS applications.
        </p>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mt-12">
          {FEATURES.map((feature) => (
            <Card
              key={feature.title}
              className="bg-zinc-900 border-zinc-800 hover:border-zinc-700 transition-colors"
            >
              <CardHeader>
                <div className="inline-flex items-center justify-center w-10 h-10 rounded-lg bg-zinc-800 border border-zinc-700 mb-3">
                  <feature.icon className="w-4 h-4 text-zinc-300" />
                </div>
                <CardTitle className="text-base">{feature.title}</CardTitle>
                <CardDescription>{feature.description}</CardDescription>
              </CardHeader>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}
