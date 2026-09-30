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
    icons: [{ src: "/icon.svg", sizes: "any", type: "image/svg+xml" }],
  };
}
