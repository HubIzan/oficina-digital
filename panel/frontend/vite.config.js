// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  base: "/estatico/app/",
  build: {
    outDir: "dist",
    assetsInlineLimit: 0,
    sourcemap: false,
    chunkSizeWarningLimit: 3000,
    rollupOptions: {
      input: { index: "index.html", isla: "isla.html" },
    },
  },
});
