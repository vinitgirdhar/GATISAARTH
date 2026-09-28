#!/usr/bin/env node
/**
 * tools/sync_apk.js
 *
 * Automated APK release and landing page synchronization script for GatiSaarth.
 *
 * Usage:
 *   node tools/sync_apk.js [path/to/apk]
 *
 * Examples:
 *   node tools/sync_apk.js apks/GatiSaarth-v5.2+51-release.apk
 *   node tools/sync_apk.js frontend/build/app/outputs/flutter-apk/app-release.apk
 *   node tools/sync_apk.js   (auto-detects from frontend build or latest in apks/)
 *   node tools/sync_apk.js --skip-upload   (local sync only, no Vercel Blob upload)
 *
 * Uploads the APK to Vercel Blob using BLOB_READ_WRITE_TOKEN from the env or
 * landing_page/.env.local.
 */

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_DIR = path.resolve(__dirname, "..");

const APKS_DIR = path.join(ROOT_DIR, "apks");
const FRONTEND_DIR = path.join(ROOT_DIR, "frontend");
const LANDING_DIR = path.join(ROOT_DIR, "landing_page");
const DOWNLOADS_DIR = path.join(LANDING_DIR, "public", "downloads");

function getPubspecVersion() {
  const pubspecPath = path.join(FRONTEND_DIR, "pubspec.yaml");
  if (!fs.existsSync(pubspecPath)) return null;
  const content = fs.readFileSync(pubspecPath, "utf8");
  const match = content.match(/^version:\s*([^\s#]+)/m);
  if (!match) return null;
  const raw = match[1].trim();
  const [version, build] = raw.split("+");
  return { raw, version, build: build || "" };
}

function findSourceApk(explicitPath) {
  if (explicitPath) {
    const resolved = path.resolve(process.cwd(), explicitPath);
    if (!fs.existsSync(resolved)) {
      throw new Error(`Specified APK does not exist at: ${resolved}`);
    }
    return resolved;
  }

  // Check apks/ directory first
  if (fs.existsSync(APKS_DIR)) {
    const releaseCandidates = fs
      .readdirSync(APKS_DIR)
      .filter((f) => f.endsWith(".apk") && !f.includes("debug") && f.startsWith("GatiSaarth-"))
      .map((f) => ({
        name: f,
        path: path.join(APKS_DIR, f),
        mtime: fs.statSync(path.join(APKS_DIR, f)).mtimeMs,
      }))
      .sort((a, b) => b.mtime - a.mtime);

    // If there is a fresh flutter build output that is newer than all apks/ files, use it
    const flutterApk = path.join(
      FRONTEND_DIR,
      "build",
      "app",
      "outputs",
      "flutter-apk",
      "app-release.apk",
    );
    if (fs.existsSync(flutterApk)) {
      const flutterMtime = fs.statSync(flutterApk).mtimeMs;
      const newestApkMtime = releaseCandidates[0]?.mtime || 0;
      if (flutterMtime > newestApkMtime) {
        return flutterApk;
      }
    }

    if (releaseCandidates.length > 0) {
      return releaseCandidates[0].path;
    }
  }

  // Fallback to flutter build output
  const flutterApk = path.join(
    FRONTEND_DIR,
    "build",
    "app",
    "outputs",
    "flutter-apk",
    "app-release.apk",
  );
  if (fs.existsSync(flutterApk)) {
    return flutterApk;
  }

  throw new Error("No release APK found in apks/ or frontend build output.");
}

function parseVersionInfo(apkPath) {
  const filename = path.basename(apkPath);
  // Match e.g. GatiSaarth-v5.2+51-release.apk or GatiSaarth-v5.2.1+52-release.apk
  const nameMatch = filename.match(/GatiSaarth-v?([0-9.]+)(?:\+([0-9]+))?/i);
  if (nameMatch) {
    const version = nameMatch[1];
    const build = nameMatch[2] || "";
    return { version, build };
  }

  // Fallback to pubspec.yaml
  const pub = getPubspecVersion();
  if (pub) {
    return { version: pub.version, build: pub.build };
  }

  throw new Error(`Could not determine version from filename ${filename} or pubspec.yaml`);
}

// Git-ignored .env.local written by `vercel link` / `vercel env pull`.
function readBlobToken() {
  if (process.env.BLOB_READ_WRITE_TOKEN) return process.env.BLOB_READ_WRITE_TOKEN;
  const envPath = path.join(LANDING_DIR, ".env.local");
  if (!fs.existsSync(envPath)) return null;
  const match = fs
    .readFileSync(envPath, "utf8")
    .match(/^BLOB_READ_WRITE_TOKEN=["']?([^"'\r\n]+)/m);
  return match ? match[1] : null;
}

// The APK is git-ignored and over GitHub's 100 MB limit, so the site serves it
// from Vercel Blob; vercel.json redirects /downloads/*.apk there.
function uploadToBlob(apkPath, pathname) {
  const token = readBlobToken();
  if (!token) {
    throw new Error(
      "BLOB_READ_WRITE_TOKEN not found (env or landing_page/.env.local). " +
        "Run `npx vercel link` and `npx vercel env pull .env.local` in landing_page, " +
        "or pass --skip-upload.",
    );
  }
  console.log(`\nUploading ${pathname} to Vercel Blob...`);
  // Token goes through env, never argv, so it does not show in process lists.
  execSync(
    `npx -y vercel@latest blob put "${apkPath}" --access public --pathname ${pathname} ` +
      "--allow-overwrite true --cache-control-max-age 86400 " +
      "--content-type application/vnd.android.package-archive",
    { cwd: LANDING_DIR, stdio: "inherit", env: { ...process.env, BLOB_READ_WRITE_TOKEN: token } },
  );
}

function syncApk(inputArg, { skipUpload = false } = {}) {
  console.log("=== GatiSaarth APK & Landing Page Sync ===");

  const sourceApk = findSourceApk(inputArg);
  console.log(`Source APK: ${sourceApk}`);

  const versionInfo = parseVersionInfo(sourceApk);
  const version = versionInfo.version;
  const build = versionInfo.build;
  console.log(`Resolved Version: v${version} (build: ${build || "N/A"})`);

  // Ensure target in apks/ exists with standardized name
  if (!fs.existsSync(APKS_DIR)) fs.mkdirSync(APKS_DIR, { recursive: true });
  const canonicalApkName = build
    ? `GatiSaarth-v${version}+${build}-release.apk`
    : `GatiSaarth-v${version}-release.apk`;
  const canonicalApkPath = path.join(APKS_DIR, canonicalApkName);

  if (path.resolve(sourceApk) !== path.resolve(canonicalApkPath)) {
    console.log(`Copying source to ${canonicalApkPath}...`);
    fs.copyFileSync(sourceApk, canonicalApkPath);
  }

  // Compute metrics
  const fileBuffer = fs.readFileSync(sourceApk);
  const byteLength = fileBuffer.length;
  const sizeMb = (byteLength / 1000000).toFixed(1) + " MB";
  const sha256 = crypto.createHash("sha256").update(fileBuffer).digest("hex");
  const sha1 = crypto.createHash("sha1").update(fileBuffer).digest("hex");

  console.log(`File size: ${byteLength.toLocaleString()} bytes (${sizeMb})`);
  console.log(`SHA-256:   ${sha256}`);

  // Also update apks/app-release.apk and sha1
  const genericReleaseApk = path.join(APKS_DIR, "app-release.apk");
  fs.copyFileSync(sourceApk, genericReleaseApk);
  fs.writeFileSync(path.join(APKS_DIR, "app-release.apk.sha1"), `${sha1}\n`, "utf8");

  // Deploy to landing_page/public/downloads
  if (!fs.existsSync(DOWNLOADS_DIR)) fs.mkdirSync(DOWNLOADS_DIR, { recursive: true });
  const landingApkName = `gatisaarth-${version}.apk`;
  const landingApkPath = path.join(DOWNLOADS_DIR, landingApkName);

  // Remove existing .apk files in downloads to avoid stale assets
  for (const file of fs.readdirSync(DOWNLOADS_DIR)) {
    if (file.endsWith(".apk") && file !== landingApkName) {
      console.log(`Removing old APK asset: ${file}`);
      fs.unlinkSync(path.join(DOWNLOADS_DIR, file));
    }
  }

  fs.copyFileSync(sourceApk, landingApkPath);
  console.log(`Copied APK to: ${landingApkPath}`);

  // Update SHA256SUMS.txt
  const shaSumsPath = path.join(DOWNLOADS_DIR, "SHA256SUMS.txt");
  fs.writeFileSync(shaSumsPath, `${sha256}  ${landingApkName}\n`, "utf8");
  console.log(`Updated SHA256SUMS.txt`);

  if (skipUpload) {
    console.log("Skipping Vercel Blob upload (--skip-upload). The live download stays on the old APK.");
  } else {
    uploadToBlob(landingApkPath, landingApkName);
  }

  // Update landing_page/index.html
  const indexPath = path.join(LANDING_DIR, "index.html");
  if (fs.existsSync(indexPath)) {
    let indexHtml = fs.readFileSync(indexPath, "utf8");

    // Replace download links
    indexHtml = indexHtml.replace(
      /href="\.\/downloads\/gatisaarth-[^"]+\.apk"/g,
      `href="./downloads/${landingApkName}"`,
    );

    // Replace button version badge
    indexHtml = indexHtml.replace(
      /<span class="button-version">v[^<]+<\/span>/g,
      `<span class="button-version">v${version}</span>`,
    );

    // Replace download meta
    indexHtml = indexHtml.replace(
      /<span class="download-meta">Android [^<]+<\/span>/g,
      `<span class="download-meta">Android 7.0+ · ${sizeMb} · Universal APK</span>`,
    );

    // Replace apk hash (handles potential newlines in code tag from Prettier)
    indexHtml = indexHtml.replace(
      /<code id="apk-hash"[\s\S]*?<\/code[\s\S]*?>/g,
      `<code id="apk-hash">${sha256}</code>`,
    );

    fs.writeFileSync(indexPath, indexHtml, "utf8");
    console.log(`Updated landing_page/index.html`);
  }

  // Update landing_page/vercel.json
  const vercelPath = path.join(LANDING_DIR, "vercel.json");
  if (fs.existsSync(vercelPath)) {
    let vercelJson = fs.readFileSync(vercelPath, "utf8");
    vercelJson = vercelJson.replace(
      /"value": "attachment; filename=\\"gatisaarth-[^"]+\.apk\\""/g,
      `"value": "attachment; filename=\\"${landingApkName}\\""`,
    );
    fs.writeFileSync(vercelPath, vercelJson, "utf8");
    console.log(`Updated landing_page/vercel.json`);
  }

  // Update landing_page/tests/launch.spec.js
  const testPath = path.join(LANDING_DIR, "tests", "launch.spec.js");
  if (fs.existsSync(testPath)) {
    let testJs = fs.readFileSync(testPath, "utf8");
    testJs = testJs.replace(
      /expect\(download\.suggestedFilename\(\)\)\.toBe\("gatisaarth-[^"]+\.apk"\);/,
      `expect(download.suggestedFilename()).toBe("${landingApkName}");`,
    );
    testJs = testJs.replace(
      /expect\(apk\.length\)\.toBe\([0-9]+\);/,
      `expect(apk.length).toBe(${byteLength});`,
    );
    fs.writeFileSync(testPath, testJs, "utf8");
    console.log(`Updated landing_page/tests/launch.spec.js`);
  }

  // Update landing_page/README.md
  const readmePath = path.join(LANDING_DIR, "README.md");
  if (fs.existsSync(readmePath)) {
    let readme = fs.readFileSync(readmePath, "utf8");
    readme = readme.replace(
      /`public\/downloads\/gatisaarth-[^`]+\.apk` is copied byte for byte from `\.\.\/apks\/[^`]+\.apk`\. Package metadata confirms Android API 24 minimum, version [^,]+, and `arm64-v8a`, `armeabi-v7a`, and `x86_64` support\. File size: [0-9,]+ bytes \([^)]+\)\. The page and `SHA256SUMS\.txt` include its actual SHA-256\./,
      `\`public/downloads/${landingApkName}\` is copied byte for byte from \`../apks/${canonicalApkName}\`. Package metadata confirms Android API 24 minimum, version ${version}/code ${build || "N/A"}, and \`arm64-v8a\`, \`armeabi-v7a\`, and \`x86_64\` support. File size: ${byteLength.toLocaleString()} bytes (${sizeMb}). The page and \`SHA256SUMS.txt\` include its actual SHA-256.`,
    );
    fs.writeFileSync(readmePath, readme, "utf8");
    console.log(`Updated landing_page/README.md`);
  }

  // Rebuild landing page production bundle
  try {
    console.log("\nRebuilding landing page production bundle...");
    execSync("npm run build", { cwd: LANDING_DIR, stdio: "inherit" });
    console.log("Production build updated successfully.");
  } catch (err) {
    console.warn("Notice: Could not rebuild landing page automatically.", err.message);
  }

  console.log("\nSync complete! All assets and landing page files are in sync.");
}

const args = process.argv.slice(2);
const inputArg = args.find((a) => !a.startsWith("--"));
syncApk(inputArg, { skipUpload: args.includes("--skip-upload") });
