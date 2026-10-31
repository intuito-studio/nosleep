import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import { GlassFilter } from "@/components/GlassFilter";
import { SmoothScroll } from "@/components/SmoothScroll";
import "lenis/dist/lenis.css";
import { DESCRIPTION, NAME, PUBLISHER, SITE_URL, TITLE } from "@/lib/site";
import "./globals.css";

// Mac visitors get SF Pro from the system stack; Inter stands in elsewhere.
const inter = Inter({ variable: "--font-inter", subsets: ["latin"] });

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: TITLE,
  description: DESCRIPTION,
  applicationName: NAME,
  keywords: [
    "keep Mac awake lid closed",
    "MacBook closed lid mode",
    "clamshell mode without display",
    "prevent Mac sleep",
    "pmset disablesleep",
    "macOS menu bar app",
    "Amphetamine alternative",
    "caffeinate lid closed",
  ],
  authors: [{ name: PUBLISHER, url: "https://intuitostudio.com" }],
  creator: PUBLISHER,
  publisher: PUBLISHER,
  category: "utilities",
  alternates: { canonical: "/" },
  openGraph: { type: "website", url: "/", siteName: NAME, title: TITLE, description: DESCRIPTION, locale: "en_US" },
  twitter: { card: "summary_large_image", title: TITLE, description: DESCRIPTION },
  robots: { index: true, follow: true },
};

export const viewport: Viewport = {
  themeColor: "#000000",
  colorScheme: "dark",
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
