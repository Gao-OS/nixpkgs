import { spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const wrapper = process.argv[2];
if (!wrapper) throw new Error("Usage: node gateway-smoke-test.mjs <openclaw-wrapper>");

const state = await mkdtemp(join(tmpdir(), "openclaw-gateway-smoke-"));
let child;
let closed;
let failure;
let exited;
let logs = "";
const interrupted = () => { failure = new Error("Gateway smoke check interrupted"); };
process.once("SIGINT", interrupted);
process.once("SIGTERM", interrupted);

try {
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const port = server.address().port;
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  const config = join(state, "openclaw.json");
  await writeFile(config, "{}\n");
  child = spawn(wrapper, [
    "gateway", "--allow-unconfigured", "--bind", "loopback",
    "--auth", "token", "--token", "smoke-test-token", "--port", String(port),
  ], {
    detached: true,
    stdio: ["ignore", "pipe", "pipe"],
    env: {
      ...process.env,
      OPENCLAW_STATE_DIR: state,
      OPENCLAW_CONFIG_PATH: config,
      OPENCLAW_NO_RESPAWN: "1",
    },
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
  console.log("OpenClaw gateway smoke check passed (/healthz ok: true)");
} catch (error) {
  console.error(`${error.stack ?? error}\n${logs}`);
  process.exitCode = 1;
} finally {
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
