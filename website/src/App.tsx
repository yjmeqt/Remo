import { Navbar } from "@/components/Navbar";
import { DemoHero } from "@/components/DemoHero/DemoHero";
import { VisionSection } from "@/components/VisionSection";
import { FeaturesSection } from "@/components/FeaturesSection";
import { Footer } from "@/components/Footer";

// TODO: add Quick Start section with install + code snippet
// TODO: add comparison table (Remo vs Appium vs XCTest)
// TODO: add SEO meta tags (og:image, description, etc.)
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
