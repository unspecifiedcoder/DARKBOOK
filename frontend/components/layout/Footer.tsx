"use client";

export function Footer() {
  return (
    <footer className="border-t border-border/50 py-4">
      <div className="max-w-7xl mx-auto px-4 flex items-center justify-between text-xs text-muted-foreground">
        <span>DarkBook - ZK Dark Pool on Monad</span>
        <div className="flex items-center gap-4">
          <span>Powered by Noir + UltraPlonk</span>
        </div>
      </div>
    </footer>
  );
}
