import { Navbar } from "@/components/Navbar";
import { DemoHero } from "@/components/DemoHero/DemoHero";

function App() {
  return (
    <div className="min-h-screen bg-[#09090b] text-zinc-50">
      <Navbar />
      <DemoHero />
    </div>
  );
}

export default App;
