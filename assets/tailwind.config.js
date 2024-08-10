// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  darkMode: 'selector',
  content: [
    "../lib/*_web.ex",
    "../lib/*_web/**/*.*ex",
    "./index.html",
    "./src/**/*.{svelte,js,ts}",
  ],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
      }
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({addVariant}) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),
    plugin(({addVariant}) => addVariant("phx-hook-loading", [".phx-hook-loading&", ".phx-hook-loading &"])),
    plugin(({addVariant}) => addVariant("phx-error", [".phx-error&", ".phx-error &"])),
    plugin(({addVariant}) => addVariant("drag-item", [".drag-item&", ".drag-item &"])),
    plugin(({addVariant}) => addVariant("drag-ghost", [".drag-ghost&", ".drag-ghost &"]))
  ]
}
