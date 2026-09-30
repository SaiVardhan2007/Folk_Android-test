import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "FOLK Tracker",
    short_name: "FOLK",
    start_url: "/",
    scope: "/",
    display: "standalone",
    background_color: "#fdf9ee",
    theme_color: "#2f3e7a",
    icons: [
      { src: "/icon-192.png", sizes: "192x192", type: "image/png" },
      { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
    ],
  };
}
