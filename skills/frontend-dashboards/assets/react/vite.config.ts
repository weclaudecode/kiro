import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Relative base so the built dist/ works from any path: S3 + CloudFront prefix, Vercel, or a subfolder.
export default defineConfig({
  base: "./",
  plugins: [react()],
  build: {
    target: "es2022",
    chunkSizeWarningLimit: 600, // the tree-shaken echarts chunk is ~510 kB min / ~170 kB gzip
    rolldownOptions: {
      output: {
        // ECharts is most of the bundle and changes rarely: own chunk, cached across app deploys.
        codeSplitting: { groups: [{ name: "echarts", test: /node_modules[\\/](echarts|zrender)[\\/]/ }] },
      },
    },
  },
});
