import { Command, Shield, Wifi } from "lucide-react";

const VALUE_PROPS = [
  {
    icon: Command,
    title: "Programmable App Control",
    description:
      "Expose named capabilities instead of forcing agents to work only through taps and pixels. Remo lets them call the app in its own language.",
  },
  {
    icon: Shield,
    title: "Debug-Only by Design",
    description:
      "#if DEBUG compilation ensures zero production runtime overhead. Remo compiles to no-ops in Release builds.",
  },
  {
    icon: Wifi,
    title: "Runtime Discovery",
    description:
      "USB for physical devices, Bonjour for simulators - agents discover available endpoints automatically at runtime.",
  },
];

export function VisionSection() {
  return (
    <section className="py-20 px-6 border-t border-zinc-800">
      <div className="max-w-4xl mx-auto text-center">
        <h2 className="text-2xl md:text-3xl font-bold tracking-tight text-zinc-50">
          Where Remo Fits
        </h2>
        <p className="text-zinc-500 mt-3 max-w-2xl mx-auto">
          Remo gives AI agents a semantic interface to running iOS apps.
          Use it for in-app capability registration and runtime control, then
          pair it with xcodebuildmcp when you need simulator automation and
          inspection outside the app boundary.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-8 mt-12 max-w-5xl mx-auto">
        {VALUE_PROPS.map((prop) => (
          <div key={prop.title} className="text-center">
            <div className="inline-flex items-center justify-center w-12 h-12 rounded-lg bg-zinc-800 border border-zinc-700 mb-4">
              <prop.icon className="w-5 h-5 text-zinc-300" />
            </div>
            <h3 className="text-lg font-semibold text-zinc-50">
              {prop.title}
            </h3>
            <p className="text-sm text-zinc-400 mt-2 leading-relaxed">
              {prop.description}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}
