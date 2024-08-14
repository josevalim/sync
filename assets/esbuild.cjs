let sveltePlugin = {
  name: "svelte",
  setup(build) {
    let svelte = require("svelte/compiler")
    let path = require("path")
    let fs = require("fs")

    build.onLoad({ filter: /\.svelte$/ }, async (args) => {
      // This converts a message in Svelte's format to esbuild's format
      let convertMessage = ({ message, start, end }) => {
        let location
        if (start && end) {
          let lineText = source.split(/\r\n|\r|\n/g)[start.line - 1]
          let lineEnd = start.line === end.line ? end.column : lineText.length
          location = {
            file: filename,
            line: start.line,
            column: start.column,
            length: lineEnd - start.column,
            lineText,
          }
        }
        return { text: message, location }
      }

      // Load the file from the file system
      let source = await fs.promises.readFile(args.path, "utf8")
      let filename = path.relative(process.cwd(), args.path)

      // Convert Svelte syntax to JavaScript
      try {
        let { js, warnings } = svelte.compile(source, { filename, customElement: true })
        let contents = js.code + `//# sourceMappingURL=` + js.map.toUrl()
        return { contents, warnings: warnings.map(convertMessage) }
      } catch (e) {
        return { errors: [convertMessage(e)] }
      }
    })
  }
};

const config = {
  entryPoints: ["./src/main.js"],
  chunkNames: "chunks/[name]-[hash]",
  bundle: true,
  format: "esm",
  splitting: true,
  target: "es2021",
  outdir: "../priv/static/assets",
  plugins: [sveltePlugin],
  logLevel: "info"
};

(async () => {
  if (process.argv.includes("--watch")) {
    const ctx = await require("esbuild").context(config);
    await ctx.watch();
  } else {
    await require("esbuild").build(config);
  }
})()
  .then(() => {
    if (process.argv.includes("--watch")) {
      // do nothing
    } else {
      process.exit(0);
    }
  })
  .catch((e) => {
    console.warn(e);
    process.exit(1)
  });

