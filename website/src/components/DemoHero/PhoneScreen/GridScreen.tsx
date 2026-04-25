import { motion, AnimatePresence } from "framer-motion";
import type { GridTab, ScrollPosition } from "../timeline";
import type { AppendedCard } from "../useTimeline";
import { SEED_CARDS, SEED_CONTACTS, hueToHsl, type SeedCard } from "./gridSeed";

interface GridScreenProps {
  tab: GridTab;
  scroll: Record<GridTab, ScrollPosition>;
  appendedCards: AppendedCard[];
}

export function GridScreen({ tab, scroll, appendedCards }: GridScreenProps) {
  return (
    <div className="absolute inset-0 flex flex-col bg-[#f2f2f2] pt-7">
      <TabStrip selected={tab} />
      <div className="flex-1 relative overflow-hidden">
        <AnimatePresence mode="wait">
          {tab === "feed" ? (
            <motion.div
              key="feed"
              initial={{ x: -20, opacity: 0 }}
              animate={{ x: 0, opacity: 1 }}
              exit={{ x: -20, opacity: 0 }}
              transition={{ duration: 0.25 }}
              className="absolute inset-0"
            >
              <FeedView scroll={scroll.feed} appended={appendedCards} />
            </motion.div>
          ) : (
            <motion.div
              key="items"
              initial={{ x: 20, opacity: 0 }}
              animate={{ x: 0, opacity: 1 }}
              exit={{ x: 20, opacity: 0 }}
              transition={{ duration: 0.25 }}
              className="absolute inset-0"
            >
              <ItemsView scroll={scroll.items} />
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

function TabStrip({ selected }: { selected: GridTab }) {
  const tabs: GridTab[] = ["feed", "items"];
  return (
    <div className="border-b border-black/[0.08] flex gap-3 px-4 h-[34px] items-stretch">
      {tabs.map((t) => {
        const active = t === selected;
        return (
          <div key={t} className="relative flex-1 flex items-center justify-center">
            <span
              className={`text-[12px] ${active ? "font-bold text-zinc-900" : "font-medium text-zinc-500"}`}
            >
              {t === "feed" ? "Feed" : "Items"}
            </span>
            {active && (
              <motion.span
                layoutId="grid-tab-underline"
                className="absolute left-0 right-0 bottom-0 h-[2px] bg-zinc-900"
              />
            )}
          </div>
        );
      })}
    </div>
  );
}

function FeedView({
  scroll,
  appended,
}: {
  scroll: ScrollPosition;
  appended: AppendedCard[];
}) {
  const left: SeedCard[] = SEED_CARDS.filter((c) => c.column === 0);
  const right: SeedCard[] = SEED_CARDS.filter((c) => c.column === 1);

  // Distribute appended cards across columns alternately.
  const appendedCards: SeedCard[] = appended.map((c, i) => ({
    id: c.id,
    title: c.title,
    aspect: 3 / 4,
    column: (i % 2) as 0 | 1,
    hue: ((SEED_CARDS.length + i + 1) * 0.318) % 1,
    showsFooter: true,
    author: c.subtitle,
    hasPlayIcon: false,
  }));
  const leftAppended = appendedCards.filter((c) => c.column === 0);
  const rightAppended = appendedCards.filter((c) => c.column === 1);

  return (
    <ScrollFrame scroll={scroll}>
      <div className="grid grid-cols-2 gap-2 px-2 pt-2 pb-6">
        <div className="flex flex-col gap-2">
          {left.map((c) => (
            <Card key={c.id} card={c} />
          ))}
          {leftAppended.map((c) => (
            <Card key={c.id} card={c} animateIn />
          ))}
        </div>
        <div className="flex flex-col gap-2">
          {right.map((c) => (
            <Card key={c.id} card={c} />
          ))}
          {rightAppended.map((c) => (
            <Card key={c.id} card={c} animateIn />
          ))}
        </div>
      </div>
    </ScrollFrame>
  );
}

function Card({ card, animateIn }: { card: SeedCard; animateIn?: boolean }) {
  return (
    <motion.div
      initial={animateIn ? { opacity: 0, scale: 0.92 } : false}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.35, ease: "easeOut" }}
      className="bg-white rounded-2xl overflow-hidden shadow-[0_1px_2px_rgba(0,0,0,0.04)]"
    >
      <div className="relative w-full" style={{ aspectRatio: `${1 / card.aspect}` }}>
        <div
          className="absolute inset-0"
          style={{ backgroundColor: hueToHsl(card.hue) }}
        />
        {card.hasPlayIcon && (
          <svg
            className="absolute top-1.5 right-1.5"
            width="13"
            height="13"
            viewBox="0 0 24 24"
            fill="white"
          >
            <circle cx="12" cy="12" r="10" fill="rgba(255,255,255,0.95)" />
            <path d="M9 7.5v9l7-4.5-7-4.5z" fill="#222" />
          </svg>
        )}
      </div>
      {card.showsFooter && (
        <div className="px-2 py-1.5">
          <div className="text-[10px] text-zinc-900 leading-tight line-clamp-2">
            {card.title}
          </div>
          {(card.author || card.likes) && (
            <div className="flex items-center gap-1 mt-1">
              <span
                className="w-2.5 h-2.5 rounded-full"
                style={{ backgroundColor: hueToHsl(card.hue + 0.1, 0.5, 0.7) }}
              />
              <span className="text-[9px] text-zinc-500 truncate flex-1">
                {card.author}
              </span>
              {card.likes && (
                <>
                  <svg width="9" height="9" viewBox="0 0 24 24" fill="none">
                    <path
                      d="M12 21s-7-4.5-7-11a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 6.5-7 11-7 11Z"
                      stroke="currentColor"
                      strokeWidth="2"
                      className="text-zinc-500"
                    />
                  </svg>
                  <span className="text-[9px] text-zinc-500">{card.likes}</span>
                </>
              )}
            </div>
          )}
        </div>
      )}
    </motion.div>
  );
}

function ItemsView({ scroll }: { scroll: ScrollPosition }) {
  return (
    <ScrollFrame scroll={scroll}>
      <div className="px-2 pt-2 pb-6 flex flex-col">
        {SEED_CONTACTS.map((c) => (
          <div key={c.id} className="flex items-center gap-2.5 px-1.5 py-1.5">
            <div
              className="w-9 h-9 rounded-full flex items-center justify-center text-white font-semibold text-[13px]"
              style={{
                background: `linear-gradient(135deg, ${hueToHsl(c.hue, 0.45, 0.92)}, ${hueToHsl(c.hue, 0.52, 0.78)})`,
              }}
            >
              {c.name.charAt(0).toUpperCase()}
            </div>
            <div className="flex-1 min-w-0">
              <div className="text-[12px] font-bold text-zinc-900 truncate">
                {c.name}
              </div>
              <div className="text-[10px] text-zinc-500 truncate">
                {c.handle}
              </div>
            </div>
          </div>
        ))}
      </div>
    </ScrollFrame>
  );
}

/** Animates content offset based on the requested scroll position. */
function ScrollFrame({
  scroll,
  children,
}: {
  scroll: ScrollPosition;
  children: React.ReactNode;
}) {
  // Translate content up so "bottom" reveals the lower portion. The exact
  // offset is approximate — we just want a clearly visible scroll motion.
  const y = scroll === "top" ? 0 : scroll === "middle" ? -90 : -180;
  return (
    <div className="absolute inset-0 overflow-hidden">
      <motion.div
        animate={{ y }}
        transition={{ duration: 0.45, ease: "easeOut" }}
      >
        {children}
      </motion.div>
    </div>
  );
}
