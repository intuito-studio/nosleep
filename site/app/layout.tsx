import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import { GlassFilter } from "@/components/GlassFilter";
import { SmoothScroll } from "@/components/SmoothScroll";
import "lenis/dist/lenis.css";
import "./globals.css";

// Mac visitors get SF Pro from the system stack; Inter stands in elsewhere.
const inter = Inter({ variable: "--font-inter", subsets: ["latin"] });

const description = "A menu bar switch that keeps a Mac running with the lid closed. Free, for macOS 14 and later.";

export const metadata: Metadata = {
  title: "NoSleep: keep a Mac running with the lid closed",
  description,
  openGraph: { title: "NoSleep", description },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#000000" },
    { media: "(prefers-color-scheme: light)", color: "#000000" },
  ],
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={inter.variable}>
      <body>
        <GlassFilter />
        <SmoothScroll />
        {children}
      </body>
    </html>
  );
}
