import { existsSync, readFileSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { dirname, resolve } from "node:path";
import { gzipSync } from "node:zlib";

/**
 * 1. Validation configuration
 */

const ROOT_DIRECTORY = resolve(import.meta.dirname, "..");
const DOCUMENTS_DIRECTORY = resolve(ROOT_DIRECTORY, "docs");
const HTML_FILES = [resolve(DOCUMENTS_DIRECTORY, "index.html"), resolve(DOCUMENTS_DIRECTORY, "tr/index.html")];
const CSS_FILE = resolve(DOCUMENTS_DIRECTORY, "style.css");
const JAVASCRIPT_FILE = resolve(DOCUMENTS_DIRECTORY, "script.js");
const ROBOTS_FILE = resolve(DOCUMENTS_DIRECTORY, "robots.txt");
const MAX_DESCRIPTION_LENGTH = 160;
const MIN_DESCRIPTION_LENGTH = 120;
const MAX_INITIAL_GZIP_BYTES = 170 * 1024;
const MAX_CHUNK_GZIP_BYTES = 80 * 1024;
const REQUIRED_BREAKPOINTS = ["75rem", "62rem", "48rem", "36rem"];
const LOCAL_REFERENCE_PATTERN = /(?:href|src)="([^"]+)"/g;
const DEVELOPER_URL = "https://tercan.net/";

const failures = [];

/**
 * 2. Shared assertions
 */

function recordFailure(message) {
  failures.push(message);
}

function assertCondition(condition, message) {
  if (!condition) {
    recordFailure(message);
  }
}

function readText(filePath) {
  return readFileSync(filePath, "utf8");
}

function getTagCount(html, tagName) {
  return (html.match(new RegExp(`<${tagName}\\b`, "gi")) ?? []).length;
}

function getMetaDescription(html) {
  const match = html.match(/<meta\s+name="description"\s+content="([^"]+)"/i);
  return match?.[1] ?? "";
}

function resolveLocalReference(htmlPath, reference) {
  const cleanReference = reference.split("#")[0].split("?")[0];
  if (!cleanReference || cleanReference.startsWith("#") || /^[a-z]+:/i.test(cleanReference)) {
    return null;
  }

  const candidate = resolve(dirname(htmlPath), cleanReference);
  if (cleanReference.endsWith("/") || (existsSync(candidate) && statSync(candidate).isDirectory())) {
    return resolve(candidate, "index.html");
  }

  return candidate;
}

/**
 * 3. HTML checks
 */

function validateHtml(htmlPath) {
  const html = readText(htmlPath);
  const relativePath = htmlPath.replace(`${ROOT_DIRECTORY}/`, "");
  const description = getMetaDescription(html);
  const footer = html.match(/<footer\b[\s\S]*?<\/footer>/i)?.[0] ?? "";

  assertCondition(/^<!DOCTYPE html>/i.test(html), `${relativePath}: HTML5 doctype is missing.`);
  assertCondition(/<html\s+lang="(?:en|tr)"/i.test(html), `${relativePath}: a supported lang attribute is missing.`);
  assertCondition(/<meta\s+charset="UTF-8">/i.test(html), `${relativePath}: UTF-8 meta declaration is missing.`);
  assertCondition(
    /<meta\s+name="viewport"\s+content="width=device-width, initial-scale=1\.0">/i.test(html),
    `${relativePath}: viewport metadata is missing.`,
  );
  assertCondition(getTagCount(html, "h1") === 1, `${relativePath}: exactly one h1 is required.`);
  assertCondition(
    description.length >= MIN_DESCRIPTION_LENGTH && description.length <= MAX_DESCRIPTION_LENGTH,
    `${relativePath}: meta description must be ${MIN_DESCRIPTION_LENGTH}-${MAX_DESCRIPTION_LENGTH} characters; found ${description.length}.`,
  );
  assertCondition(/<link\s+rel="canonical"/i.test(html), `${relativePath}: canonical URL is missing.`);
  assertCondition((html.match(/hreflang=/g) ?? []).length >= 3, `${relativePath}: hreflang links are incomplete.`);
  assertCondition((html.match(/property="og:/g) ?? []).length >= 7, `${relativePath}: Open Graph metadata is incomplete.`);
  assertCondition((html.match(/name="twitter:/g) ?? []).length >= 4, `${relativePath}: Twitter metadata is incomplete.`);
  assertCondition(/"@type": "SoftwareApplication"/.test(html), `${relativePath}: SoftwareApplication JSON-LD is missing.`);
  assertCondition(/class="theme-toggle"/.test(html), `${relativePath}: theme control is missing.`);
  assertCondition(!/class="version-line"/.test(html), `${relativePath}: removed hero version line is still present.`);
  assertCondition(!footer.includes("GPL-2.0"), `${relativePath}: removed footer license text is still present.`);
  assertCondition(!footer.includes("data-current-year"), `${relativePath}: removed footer copyright line is still present.`);
  assertCondition(/class="footer-terminal-icon"/.test(footer), `${relativePath}: footer terminal icon is missing.`);
  assertCondition(!/hreflang=/.test(footer), `${relativePath}: footer language link is still present.`);
  assertCondition(
    /href="https:\/\/github\.com\/tercan\/tesviye\/issues"/.test(footer),
    `${relativePath}: footer issue link is missing.`,
  );
  assertCondition(
    (footer.match(/class="footer-link"/g) ?? []).length === 3,
    `${relativePath}: footer must contain exactly three navigation links.`,
  );
  assertCondition(/data-label-system=/.test(html), `${relativePath}: system theme label is missing.`);
  assertCondition(/data-label-light=/.test(html), `${relativePath}: light theme label is missing.`);
  assertCondition(/data-label-dark=/.test(html), `${relativePath}: dark theme label is missing.`);
  assertCondition(
    /<main\s+id="main-content"\s+tabindex="-1">/.test(html),
    `${relativePath}: the skip-link target must support programmatic focus.`,
  );
  assertCondition(
    (html.match(new RegExp(`href="${DEVELOPER_URL}"`, "g")) ?? []).length >= 1,
    `${relativePath}: visible developer link is missing.`,
  );
  assertCondition(
    html.includes(`"url": "${DEVELOPER_URL}"`),
    `${relativePath}: structured developer URL is invalid.`,
  );

  const images = html.match(/<img\b[^>]*>/gi) ?? [];
  images.forEach((image, index) => {
    assertCondition(/\salt="[^"]*"/i.test(image), `${relativePath}: image ${index + 1} does not define alt text.`);
    assertCondition(/\swidth="\d+"/i.test(image), `${relativePath}: image ${index + 1} does not define width.`);
    assertCondition(/\sheight="\d+"/i.test(image), `${relativePath}: image ${index + 1} does not define height.`);
  });

  const blocks = html.match(/<(section|article)\b[\s\S]*?<\/\1>/gi) ?? [];
  blocks.forEach((block, index) => {
    assertCondition(/<h[1-6]\b/i.test(block), `${relativePath}: section or article ${index + 1} has no heading.`);
  });

  const references = [...html.matchAll(LOCAL_REFERENCE_PATTERN)].map((match) => match[1]);
  for (const match of html.matchAll(/\bsrcset="([^"]+)"/g)) {
    references.push(...match[1].split(",").map((candidate) => candidate.trim().split(/\s+/)[0]));
  }
  references.forEach((reference) => {
    const resolvedReference = resolveLocalReference(htmlPath, reference);
    if (resolvedReference) {
      assertCondition(existsSync(resolvedReference), `${relativePath}: local reference does not exist: ${reference}`);
    }
  });
}

/**
 * 4. CSS and JavaScript checks
 */

function validateCss() {
  const css = readText(CSS_FILE);
  const cssWithoutRoot = css.replace(/:root\s*\{[\s\S]*?\n\}/, "");

  assertCondition(!/gradient\s*\(/i.test(css), "docs/style.css: gradients are forbidden.");
  assertCondition(!/#[0-9a-f]{3,8}\b/i.test(cssWithoutRoot), "docs/style.css: colors must use design tokens.");
  assertCondition(!/\b(?!1px\b)\d+(?:\.\d+)?px\b/i.test(css), "docs/style.css: sizing must use rem units.");
  assertCondition(/--border-radius:\s*0;/.test(css), "docs/style.css: the radius token must remain zero.");
  assertCondition(!/(?<!-)border-radius:\s*(?!var\(|0(?:[;\s]))/i.test(css), "docs/style.css: non-token radius found.");
  assertCondition(/:focus-visible/.test(css), "docs/style.css: visible keyboard focus styles are missing.");
  assertCondition(/prefers-reduced-motion/.test(css), "docs/style.css: reduced-motion handling is missing.");
  assertCondition(/scroll-behavior:\s*smooth/.test(css), "docs/style.css: smooth in-page scrolling is missing.");
  assertCondition(/:root\[data-theme="dark"\]/.test(css), "docs/style.css: dark theme token mapping is missing.");
  assertCondition(
    /\.eyebrow\s*\{[\s\S]*?font-weight:\s*var\(--font-weight-medium\);[\s\S]*?letter-spacing:\s*0;[\s\S]*?\}/.test(css),
    "docs/style.css: shared eyebrow typography is invalid.",
  );

  REQUIRED_BREAKPOINTS.forEach((breakpoint) => {
    assertCondition(
      css.includes(`@media (max-width: ${breakpoint})`),
      `docs/style.css: required ${breakpoint} breakpoint is missing.`,
    );
  });
}

function validateJavaScript() {
  const source = readText(JAVASCRIPT_FILE);
  assertCondition(!/console\.log\s*\(/.test(source), "docs/script.js: console.log is not allowed.");
  assertCondition(/"use strict";/.test(source), "docs/script.js: strict mode is missing.");
  assertCondition(/localStorage\.getItem/.test(source), "docs/script.js: persisted theme loading is missing.");
  assertCondition(/localStorage\.setItem/.test(source), "docs/script.js: persisted theme saving is missing.");
  assertCondition(/prefers-color-scheme: dark/.test(source), "docs/script.js: system theme detection is missing.");
  assertCondition(/event\.preventDefault\(\)/.test(source), "docs/script.js: hashless in-page navigation is missing.");
  assertCondition(/scrollIntoView\(/.test(source), "docs/script.js: in-page target scrolling is missing.");
  assertCondition(/addEventListener\("hashchange"/.test(source), "docs/script.js: direct hash cleanup is missing.");
  assertCondition(/history\.replaceState\(/.test(source), "docs/script.js: visible hash cleanup is missing.");
  assertCondition(gzipSync(source).byteLength <= MAX_CHUNK_GZIP_BYTES, "docs/script.js: lazy chunk budget exceeded.");
}

/**
 * 5. Performance budget
 */

function validateInitialPayload() {
  const initialFiles = [
    CSS_FILE,
    JAVASCRIPT_FILE,
    resolve(DOCUMENTS_DIRECTORY, "assets/tesviye-icon-36.webp"),
    resolve(DOCUMENTS_DIRECTORY, "assets/tesviye-image-resizer-screenshot-light.webp"),
    resolve(DOCUMENTS_DIRECTORY, "assets/tesviye-image-resizer-screenshot-dark.webp"),
  ];
  const gzipBytes = initialFiles.reduce((total, filePath) => total + gzipSync(readFileSync(filePath)).byteLength, 0);

  assertCondition(gzipBytes <= MAX_INITIAL_GZIP_BYTES, `docs/: initial gzip budget exceeded; found ${gzipBytes} bytes.`);
  initialFiles.forEach((filePath) => {
    assertCondition(statSync(filePath).size > 0, `${filePath}: required initial asset is empty.`);
  });
}

function validateRobotsFile() {
  const robots = readText(ROBOTS_FILE);
  assertCondition(/^User-agent:\s*\*$/m.test(robots), "docs/robots.txt: wildcard user agent is missing.");
  assertCondition(/^Allow:\s*\/$/m.test(robots), "docs/robots.txt: root allow rule is missing.");
  assertCondition(
    /^Sitemap:\s*https:\/\/tercan\.github\.io\/tesviye\/sitemap\.xml$/m.test(robots),
    "docs/robots.txt: sitemap declaration is invalid.",
  );
}

/**
 * 6. Screenshot and release consistency
 */

function validateScreenshotsAndRelease() {
  const readme = readText(resolve(ROOT_DIRECTORY, "README.md"));
  const changelog = readText(resolve(ROOT_DIRECTORY, "CHANGELOG.md"));
  const project = readText(
    resolve(ROOT_DIRECTORY, "tesviye.xcodeproj/project.pbxproj"),
  );
  const versions = new Set(
    [...project.matchAll(/MARKETING_VERSION = ([^;]+);/g)].map(
      (match) => match[1],
    ),
  );
  assertCondition(
    versions.size === 1,
    "Xcode targets must share one application version.",
  );
  const [version] = versions;
  validateDownload(version, readme);
  assertCondition(
    readme.includes(`Version ${version}`),
    "README.md: application version is not synchronized.",
  );
  assertCondition(
    changelog.includes(`## [${version}] - `),
    "CHANGELOG.md: current version entry is missing.",
  );

  for (const theme of ["light", "dark"]) {
    const basename = `tesviye-image-resizer-screenshot-${theme}`;
    const pngPath = resolve(DOCUMENTS_DIRECTORY, `assets/${basename}.png`);
    const webpPath = resolve(DOCUMENTS_DIRECTORY, `assets/${basename}.webp`);
    assertCondition(
      existsSync(pngPath) && existsSync(webpPath),
      `${theme}: PNG/WebP screenshot pair is missing.`,
    );
    if (!existsSync(pngPath)) continue;
    const png = readFileSync(pngPath);
    const width = png.readUInt32BE(16);
    const height = png.readUInt32BE(20);
    assertCondition(
      readme.includes(`docs/assets/${basename}.png`),
      `README.md: ${theme} screenshot is missing.`,
    );

    for (const htmlPath of HTML_FILES) {
      const html = readText(htmlPath);
      const image =
        (html.match(/<img\b[^>]*>/g) ?? []).find((tag) =>
          tag.includes(`${basename}.png`),
        ) ?? "";
      assertCondition(
        image.includes(`width="${width}"`) &&
          image.includes(`height="${height}"`),
        `${htmlPath}: ${theme} screenshot dimensions are stale.`,
      );
      assertCondition(
        html.includes(`app-screenshot-picture--${theme}`),
        `${htmlPath}: ${theme} screenshot variant is missing.`,
      );
      assertCondition(
        html.includes(`"softwareVersion": "${version}"`),
        `${htmlPath}: softwareVersion is not synchronized.`,
      );
      assertCondition(
        !html.includes("screenshoot"),
        `${htmlPath}: obsolete screenshot reference remains.`,
      );
    }
  }
}

function validateDownload(version, readme) {
  const filename = `Tesviye-${version}-universal.dmg`;
  const publicUrl = `https://tercan.github.io/tesviye/downloads/${filename}`;
  const sourceUrl = `https://github.com/tercan/tesviye/archive/refs/tags/v${version}.zip`;
  const packagePath = resolve(DOCUMENTS_DIRECTORY, "downloads", filename);
  const checksumPath = resolve(DOCUMENTS_DIRECTORY, "downloads/SHA256SUMS");
  const versionedChecksumPath = `${packagePath}.sha256`;
  assertCondition(existsSync(packagePath), `Missing public DMG: ${filename}`);
  assertCondition(existsSync(checksumPath), "Public SHA256SUMS is missing.");
  if (!existsSync(packagePath) || !existsSync(checksumPath)) return;

  const packageBytes = readFileSync(packagePath);
  const checksum = createHash("sha256").update(packageBytes).digest("hex");
  assertCondition(packageBytes.length > 0 && packageBytes.length < 50 * 1024 * 1024, "Public DMG is empty or exceeds the 50 MB repository budget.");
  assertCondition(readText(checksumPath).trim() === `${checksum}  ${filename}`, "Public DMG SHA-256 does not match SHA256SUMS.");
  assertCondition(existsSync(versionedChecksumPath) && readText(versionedChecksumPath).trim() === `${checksum}  ${filename}`, "Versioned DMG checksum is missing or invalid.");
  assertCondition(readme.includes(publicUrl) && readme.includes(sourceUrl), "README download/source links are not version-matched.");

  for (const htmlPath of HTML_FILES) {
    const html = readText(htmlPath);
    assertCondition(html.includes(`downloads/${filename}" download="${filename}"`), `${htmlPath}: direct DMG download link is missing.`);
    assertCondition(html.includes(`"downloadUrl": "${publicUrl}"`), `${htmlPath}: structured downloadUrl does not point to the DMG.`);
    assertCondition(html.includes(sourceUrl), `${htmlPath}: matching source archive link is missing.`);
    assertCondition(html.includes('id="download-notice"'), `${htmlPath}: signing information is missing.`);
  }
}

/**
 * 7. Validation entrypoint
 */

HTML_FILES.forEach(validateHtml);
validateCss();
validateJavaScript();
validateInitialPayload();
validateRobotsFile();
validateScreenshotsAndRelease();

if (failures.length > 0) {
  process.stderr.write(`${failures.join("\n")}\n`);
  process.exitCode = 1;
} else {
  process.stdout.write("GitHub Pages validation passed.\n");
}
