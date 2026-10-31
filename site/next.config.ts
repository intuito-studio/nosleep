import type { NextConfig } from "next";

// Static files only, so the page can be hosted anywhere.
const nextConfig: NextConfig = {
  output: "export",
  images: { unoptimized: true },
};

export default nextConfig;
