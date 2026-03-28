export function Footer() {
  return (
    <footer className="border-t border-zinc-800 px-6 py-6">
      <div className="max-w-5xl mx-auto flex items-center justify-between text-sm text-zinc-500">
        <span className="font-semibold text-zinc-400">Remo</span>
        <div className="flex items-center gap-4">
          <a
            href="https://github.com/yjmeqt/Remo"
            target="_blank"
            rel="noopener noreferrer"
            className="hover:text-zinc-300 transition-colors"
          >
            GitHub
          </a>
          <span>MIT License</span>
          <span>Built by Yi Jiang</span>
        </div>
      </div>
    </footer>
  );
}
