export default {
  external: ["@capacitor/core", "howler"],
  input: "dist/index.js",
  output: [
    {
      file: "dist/plugin.js",
      format: "iife",
      globals: {
        "@capacitor/core": "capacitorExports",
        howler: "Howler",
      },
      inlineDynamicImports: true,
      name: "capacitorCapacitorMusicKit",
      sourcemap: true,
    },
    {
      file: "dist/plugin.cjs.js",
      format: "cjs",
      inlineDynamicImports: true,
      sourcemap: true,
    },
  ],
};
