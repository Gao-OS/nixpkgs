import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer as createHttpServer, request as httpRequest } from "node:http";
import { createRequire } from "node:module";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { promisify } from "node:util";

const wrapper = process.argv[2];
if (!wrapper) throw new Error("Usage: node gateway-smoke-test.mjs <openclaw-wrapper>");

const state = await mkdtemp(join(tmpdir(), "openclaw-gateway-smoke-"));
let child;
let closed;
let failure;
let exited;
let proxy;
const sockets = new Set();
const healthAbort = new AbortController();
let logs = "";
const interrupted = () => {
  failure = new Error("Gateway smoke check interrupted");
  healthAbort.abort();
};
process.once("SIGINT", interrupted);
process.once("SIGTERM", interrupted);

try {
  const require = createRequire(join(dirname(dirname(resolve(wrapper))), "lib/node_modules/openclaw/package.json"));
  assert.equal(typeof require("@openclaw/proxyline").ProxylineNodeProxyAgent, "function",
    "Bundled @openclaw/proxyline must export ProxylineNodeProxyAgent");
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const port = server.address().port;
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  const config = join(state, "openclaw.json");
  await writeFile(config, JSON.stringify({
    gateway: { mode: "local", port, auth: { mode: "token", token: "smoke-test-token" } },
  }));
  const env = {
    ...process.env,
    OPENCLAW_STATE_DIR: state,
    OPENCLAW_CONFIG_PATH: config,
    OPENCLAW_NO_RESPAWN: "1",
  };
  child = spawn(wrapper, [
    "gateway", "--allow-unconfigured", "--bind", "loopback",
    "--auth", "token", "--token", "smoke-test-token", "--port", String(port),
  ], {
    detached: true,
    stdio: ["ignore", "pipe", "pipe"],
    env,
  });
  child.stdout.on("data", chunk => { logs += chunk; });
  child.stderr.on("data", chunk => { logs += chunk; });
  child.once("error", error => { failure = error; });
  exited = new Promise(resolve => {
    child.once("close", (code, signal) => { closed = { code, signal }; resolve(); });
  });

  const deadline = Date.now() + 60_000;
  let healthy = false;
  while (Date.now() < deadline) {
    if (failure) throw failure;
    if (closed) throw new Error(`Gateway exited: ${JSON.stringify(closed)}`);
    try {
      const response = await fetch(`http://127.0.0.1:${port}/healthz`, {
        signal: AbortSignal.timeout(1000),
      });
      if (response.ok && (await response.json()).ok === true) {
        healthy = true;
        break;
      }
    } catch { /* The gateway may still be starting. */ }
    await delay(250);
  }
  if (!healthy) throw new Error("Gateway did not become healthy within 60 seconds");

  let forwardedProbes = 0;
  const track = socket => {
    sockets.add(socket);
    socket.once("close", () => sockets.delete(socket));
    socket.on("error", () => socket.destroy());
    return socket;
  };
  proxy = createHttpServer((request, response) => {
    let target;
    try { target = new URL(request.url); }
    catch { response.writeHead(400).end(); return; }
    if (target.origin !== `http://127.0.0.1:${port}` || target.pathname !== "/startupz" || request.method !== "GET") {
      response.writeHead(403).end();
      return;
    }
    const forwarded = httpRequest(target, { method: request.method, headers: request.headers }, upstream => {
      response.writeHead(upstream.statusCode, upstream.headers);
      upstream.once("end", () => { if (upstream.statusCode === 200) forwardedProbes++; });
      upstream.pipe(response);
    });
    forwarded.once("socket", track);
    forwarded.once("error", () => response.destroy());
    request.pipe(forwarded);
  });
  proxy.on("connection", track);
  await new Promise((resolve, reject) => {
    proxy.once("error", reject);
    proxy.listen(0, "127.0.0.1", resolve);
  });
  const proxyUrl = `http://127.0.0.1:${proxy.address().port}`;
  const { stdout, stderr } = await promisify(execFile)(wrapper, ["health", "--timeout", "30000", "--json"], {
    env: {
      ...env,
      HTTP_PROXY: proxyUrl, HTTPS_PROXY: proxyUrl, ALL_PROXY: proxyUrl,
      http_proxy: proxyUrl, https_proxy: proxyUrl, all_proxy: proxyUrl,
      NO_PROXY: "", no_proxy: "",
    },
    timeout: 35_000,
    killSignal: "SIGKILL",
    signal: healthAbort.signal,
  });
  logs += `\nHealth stdout:\n${stdout}\nHealth stderr:\n${stderr}`;
  assert.equal(JSON.parse(stdout).ok, true, "Proxied gateway health must report ok: true");
  assert.ok(forwardedProbes > 0, "Gateway health must successfully proxy its /startupz probe");
  console.log("OpenClaw gateway smoke check passed (/healthz and proxied health ok: true)");
} catch (error) {
  console.error(`${error.stack ?? error}\n${error.stdout ?? ""}\n${error.stderr ?? ""}\n${logs}`);
  process.exitCode = 1;
} finally {
  for (const socket of sockets) socket.destroy();
  if (proxy?.listening) await new Promise(resolve => proxy.close(resolve));
  if (child?.pid) {
    const killGroup = signal => {
      try { process.kill(-child.pid, signal); }
      catch (error) { if (error.code !== "ESRCH") throw error; }
    };
    killGroup("SIGTERM");
    await Promise.race([exited, delay(3000, undefined, { ref: false })]);
    killGroup("SIGKILL");
    await exited;
  }
  await rm(state, { recursive: true, force: true });
  process.removeListener("SIGINT", interrupted);
  process.removeListener("SIGTERM", interrupted);
}
