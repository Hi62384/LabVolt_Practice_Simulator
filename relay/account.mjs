import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync } from "node:fs";
import { readFile, writeFile, rm, cp, mkdir, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const [action, workspace, accountId] = process.argv.slice(2);
const source = fileURLToPath(new URL(".", import.meta.url));
const wrangler = resolve(source, "node_modules/wrangler/bin/wrangler.js");
const env = {
  ...process.env,
  XDG_CONFIG_HOME: join(workspace, "cloudflare"),
  CLOUDFLARE_AUTH_USE_KEYRING: "true",
  WRANGLER_SEND_METRICS: "false",
};
for (const key of ["CLOUDFLARE_API_TOKEN", "CLOUDFLARE_API_KEY", "CLOUDFLARE_EMAIL",
  "CLOUDFLARE_ACCOUNT_ID", "CF_API_TOKEN", "CF_API_KEY", "CF_EMAIL", "CF_ACCOUNT_ID"]) {
  delete env[key];
}

const profile = "labvolt-relay";
const loginCancel = join(workspace, "cancel-login");
const workersDashboard = id => "https://dash.cloudflare.com/" + id + "/workers-and-pages";

async function prepareKeyring() {
  const legacy = join(homedir(), ".wrangler");
  const exists = await stat(legacy).then(info => info.isDirectory(), () => false);
  const config = exists ? legacy : join(env.XDG_CONFIG_HOME, ".wrangler");
  const modules = join(config, "native", "keyring", "node_modules", "@napi-rs");
  await mkdir(modules, { recursive: true });
  for (const name of ["keyring", "keyring-win32-x64-msvc"]) {
    await cp(join(source, "node_modules", "@napi-rs", name), join(modules, name), {
      recursive: true, force: false,
    });
  }
}

function run(args, namedProfile = true) {
  return new Promise((resolveRun, reject) => {
    const cancelled = () => action === "login" && existsSync(loginCancel);
    if (cancelled()) {
      reject(new Error("Cloudflare sign in cancelled."));
      return;
    }
    const child = spawn(process.execPath, [wrangler, ...args, ...(namedProfile ? ["--profile", profile] : [])], {
      cwd: workspace, env, windowsHide: true, stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const watchCancel = action === "login" ? setInterval(() => {
      if (cancelled()) child.kill();
    }, 250) : undefined;
    child.stdout.setEncoding("utf8").on("data", data => { stdout += data; });
    child.stderr.setEncoding("utf8").on("data", data => { stderr += data; });
    child.on("error", reject);
    child.on("close", code => {
      clearInterval(watchCancel);
      if (cancelled()) reject(new Error("Cloudflare sign in cancelled."));
      else if (code === 0) resolveRun(stdout);
      else reject(new Error((stderr || stdout).replace(/\x1b\[[0-9;]*m/g, "")
        .split(/Logs were written to/i)[0].trim().slice(0, 900)));
    });
  });
}

async function accountIdentity() {
  const identity = JSON.parse(await run(["whoami", "--json"], false));
  const accounts = (identity.accounts ?? []).filter(account => /^[a-f0-9]{32}$/.test(account.id));
  if (!accounts.length) throw new Error("Create a Cloudflare account in the browser and try again.");
  return { email: identity.email, accounts };
}

async function setup() {
  await prepareKeyring();
  if (action === "logout") {
    await run(["auth", "delete", profile], false);
    return {};
  }
  if (action === "login") {
    try {
      await run(["auth", "activate", profile], false);
      return await accountIdentity();
    } catch {
      await run(["auth", "create", profile, "--scopes",
        "account:read", "user:read", "workers:write", "workers_scripts:write"], false);
      await run(["auth", "activate", profile], false);
      return await accountIdentity();
    }
  }
  if (action !== "deploy" || !/^[a-f0-9]{32}$/.test(accountId)) {
    throw new Error("Select a Cloudflare account first.");
  }
  const hostKey = randomBytes(32).toString("hex");
  const configuration = JSON.parse(await readFile(join(source, "wrangler.jsonc"), "utf8"));
  configuration.account_id = accountId;
  configuration.main = join(source, "worker.mjs");
  configuration.vars = { REQUIRE_HOST_KEY: "1" };
  await writeFile(join(workspace, "wrangler.json"), JSON.stringify(configuration));
  const secretFile = join(workspace, "deploy-secret.json");
  await writeFile(secretFile, JSON.stringify({ HOST_KEY: hostKey }));
  try {
    let output;
    try {
      output = await run(["deploy", "--config", "wrangler.json", "--secrets-file", secretFile]);
    } catch (error) {
      if (error.message.includes("/workers/onboarding")) {
        return { needs_onboarding: true, onboarding_url: workersDashboard(accountId) };
      }
      throw error;
    }
    const endpoint = output.match(/https:\/\/labvolt-relay\.[a-z0-9-]+\.workers\.dev\b/i)?.[0];
    if (!endpoint) throw new Error("Cloudflare did not return a workers.dev address. Enable your Workers subdomain in Cloudflare and try again.");
    return { host: new URL(endpoint).hostname, host_key: hostKey, account_id: accountId };
  } finally {
    await rm(secretFile, { force: true });
  }
}

let result;
try {
  result = { ok: true, ...await setup() };
} catch (error) {
  result = { ok: false, error: error.message || "Cloudflare setup failed." };
}
await writeFile(join(workspace, "result.json"), JSON.stringify(result));
