import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, extname, resolve } from "node:path";
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
  if (cleanReference.endsWith("/") || extname(candidate) === "") {
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
  assertCondition(gzipSync(source).byteLength <= MAX_CHUNK_GZIP_BYTES, "docs/script.js: lazy chunk budget exceeded.");
}

/**
 * 5. Performance budget
 */

function validateInitialPayload() {
  const initialFiles = [CSS_FILE, JAVASCRIPT_FILE, resolve(DOCUMENTS_DIRECTORY, "assets/tesviye-icon-36.webp")];
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
 * 6. Validation entrypoint
 */

HTML_FILES.forEach(validateHtml);
validateCss();
validateJavaScript();
validateInitialPayload();
validateRobotsFile();

if (failures.length > 0) {
  process.stderr.write(`${failures.join("\n")}\n`);
  process.exitCode = 1;
} else {
  process.stdout.write("GitHub Pages validation passed.\n");
}
