// Renders OpenMoji SVGs to small PNGs for the app (duk bundle).
// usage: node render_icons.js <svg dir> <out dir> <size> <hexcode>...
// Runs with NODE_PATH pointing at data/tools/svgrender/node_modules (@resvg/resvg-js).
const fs = require("fs");
const path = require("path");
const { Resvg } = require("@resvg/resvg-js");

const [svgDir, outDir, size, ...codes] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
let n = 0;
for (const code of codes) {
  if (!/^[0-9A-F-]+$/.test(code)) continue; // hexcodes only: never a path
  const src = path.join(svgDir, `${code}.svg`);
  if (!fs.existsSync(src)) continue;
  const png = new Resvg(fs.readFileSync(src), {
    fitTo: { mode: "width", value: Number(size) },
  })
    .render()
    .asPng();
  fs.writeFileSync(path.join(outDir, `${code}.png`), png);
  n++;
}
console.log(`icons: ${n}`);
