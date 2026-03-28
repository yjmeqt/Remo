import { Navbar } from "@/components/Navbar";
import { DemoHero } from "@/components/DemoHero/DemoHero";
import { VisionSection } from "@/components/VisionSection";
import { FeaturesSection } from "@/components/FeaturesSection";
import { Footer } from "@/components/Footer";

function App() {
  return (
    <div className="min-h-screen bg-[#09090b] text-zinc-50 flex flex-col">
      <Navbar />
      <main className="flex-1">
        <DemoHero />
        <VisionSection />
        <FeaturesSection />
      </main>
      <Footer />
    </div>
  );
}

export default App;
