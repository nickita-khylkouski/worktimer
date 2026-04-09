#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createWriteStream, existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const packageJson = JSON.parse(readFileSync(path.join(__dirname, "..", "package.json"), "utf8"));

const APP_NAME = "WorkTimer";
const VERSION = packageJson.version;
const TAG = `v${VERSION}`;
const REPO = "nickita-khylkouski/worktimer";
const ZIP_NAME = `${APP_NAME}-macOS.zip`;
const DEFAULT_INSTALL_DIR = process.env.WORKTIMER_INSTALL_DIR || path.join(os.homedir(), "Applications");
const RELEASE_ZIP_URL = `https://github.com/${REPO}/releases/download/${TAG}/${ZIP_NAME}`;

async function main() {
  const [command = "install", ...args] = process.argv.slice(2);

  if (command === "help" || command === "--help" || command === "-h") {
    printHelp();
    return;
  }

  if (process.platform !== "darwin") {
    fail("WorkTimer is a macOS app. This installer only runs on macOS.");
  }

  switch (command) {
    case "install":
      await installCommand(args);
      return;
    case "open":
      openInstalledApp(resolveInstallDir(args));
      return;
    case "doctor":
      doctor(resolveInstallDir(args));
      return;
    default:
      fail(`Unknown command: ${command}`);
  }
}

function resolveInstallDir(args) {
  const appDirFlag = args.find((arg) => arg.startsWith("--app-dir="));
  if (appDirFlag) {
    return appDirFlag.slice("--app-dir=".length);
  }
  return DEFAULT_INSTALL_DIR;
}

async function installCommand(args) {
  const installDir = resolveInstallDir(args);
  const shouldOpen = !args.includes("--no-open");
  const appPath = path.join(installDir, `${APP_NAME}.app`);
  const tempDir = path.join(os.tmpdir(), `worktimer-install-${Date.now()}`);
  const zipPath = path.join(tempDir, ZIP_NAME);

  mkdirSync(tempDir, { recursive: true });
  mkdirSync(installDir, { recursive: true });

  console.log(`Downloading ${RELEASE_ZIP_URL}`);
  await downloadFile(RELEASE_ZIP_URL, zipPath);

  const unpackDir = path.join(tempDir, "unpacked");
  mkdirSync(unpackDir, { recursive: true });
  run("ditto", ["-x", "-k", zipPath, unpackDir]);

  const unpackedApp = path.join(unpackDir, `${APP_NAME}.app`);
  if (!existsSync(unpackedApp)) {
    fail(`Downloaded archive did not contain ${APP_NAME}.app`);
  }

  rmSync(appPath, { recursive: true, force: true });
  run("cp", ["-R", unpackedApp, appPath]);

  console.log(`Installed ${appPath}`);
  console.log("First run:");
  console.log("- Move WorkTimer.app into /Applications or ~/Applications before granting permissions");
  console.log("- Open the app");
  console.log("- Use the Setup card to grant Accessibility and Input Monitoring if you want typing and mouse stats");

  if (shouldOpen) {
    openInstalledApp(installDir);
  }
}

function openInstalledApp(installDir) {
  const appPath = path.join(installDir, `${APP_NAME}.app`);
  if (!existsSync(appPath)) {
    fail(`WorkTimer.app was not found at ${appPath}`);
  }
  run("open", ["-na", appPath]);
  console.log(`Opened ${appPath}`);
}

function doctor(installDir) {
  const candidates = [
    path.join(installDir, `${APP_NAME}.app`),
    path.join(os.homedir(), "Applications", `${APP_NAME}.app`),
    path.join("/Applications", `${APP_NAME}.app`)
  ];

  const found = candidates.find((candidate) => existsSync(candidate));
  if (!found) {
    fail("WorkTimer.app was not found in the expected Applications folders.");
  }

  console.log(`App: ${found}`);
  try {
    const output = execFileSync("spctl", ["--assess", "--type", "execute", "--verbose=4", found], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"]
    });
    process.stdout.write(output);
  } catch (error) {
    if (error.stdout) process.stdout.write(error.stdout);
    if (error.stderr) process.stdout.write(error.stderr);
  }
}

async function downloadFile(url, destination) {
  const response = await fetch(url);
  if (!response.ok || !response.body) {
    fail(`Download failed: ${response.status} ${response.statusText}`);
  }

  const file = createWriteStream(destination);
  await new Promise((resolve, reject) => {
    Readable.fromWeb(response.body).pipe(file);
    file.on("finish", resolve);
    file.on("error", reject);
  });
}

function run(command, args) {
  execFileSync(command, args, { stdio: "inherit" });
}

function printHelp() {
  console.log(`WorkTimer ${VERSION}

Usage:
  npx worktimer
  npx worktimer install [--app-dir=/Applications] [--no-open]
  npx worktimer open [--app-dir=/Applications]
  npx worktimer doctor [--app-dir=/Applications]

Default:
  install the latest packaged WorkTimer.app from GitHub releases into ~/Applications
`);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

await main();
