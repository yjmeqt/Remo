import { Button } from "@/components/ui/button";

export function Navbar() {
  return (
    <nav className="flex items-center justify-between px-6 py-3 border-b border-zinc-800">
      <span className="text-lg font-bold tracking-tight text-zinc-50">
        Remo
      </span>
      <div className="flex items-center gap-4">
        <a
          href="https://github.com/yjmeqt/Remo"
          target="_blank"
          rel="noopener noreferrer"
          className="text-sm text-zinc-400 hover:text-zinc-50 transition-colors"
        >
          GitHub
        </a>
        {/* TODO: link to README quick-start section or docs site */}
        <Button size="sm">Get Started</Button>
      </div>
    </nav>
  );
}
