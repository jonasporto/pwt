#!/usr/bin/env node
// pwt router: a stable public port per worktree, owned by this process.
//
// While a worktree's server runs, its public port forwards to it (HTTP and
// WebSocket upgrades, X-Forwarded-* set). While it is stopped, the public
// port stays open: the first request runs `pwt server <wt> --bg`, a browser
// gets a page that shows the boot steps live, and other clients are held
// until the server listens. Servers nobody reached for idle_minutes are
// stopped with `pwt servers stop --idle`, which refuses while they are busy.
//
// Naming, policy and job control live in bash (lib/pwt/router.sh): this file
// asks `pwt router routes --porcelain` what exists and calls pwt to act, so
// the router and the CLI can never disagree about which server is which.
// No dependencies: node's http/net only.

"use strict";

const http = require("http");
const net = require("net");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");

const PWT_DIR = process.env.PWT_DIR || path.join(os.homedir(), ".pwt");
const PWT_BIN = process.env.PWT_BIN || "pwt";
const ROUTER_DIR = path.join(PWT_DIR, "router");
const CONFIG_FILE = path.join(PWT_DIR, "config");
const ACTIVITY_FILE = path.join(ROUTER_DIR, "activity");
const REFRESH_MS = Number(process.env.PWT_ROUTER_REFRESH_MS || 30000);
const IDLE_TICK_MS = Number(process.env.PWT_ROUTER_IDLE_TICK_MS || 15000);

const DEFAULTS = {
  port: "7600",
  listen: "127.0.0.1,::1",
  host_routing: "false",
  hold_seconds: "30",
  boot_timeout: "120",
  idle_minutes: "30",
  expose_logs: "true",
};

function log(msg) {
  console.log(`${new Date().toISOString()} ${msg}`);
}

// ---------------------------------------------------------------- config

function unescapeValue(v) {
  return v.replace(/\\(n|t|r|\\)/g, (_, c) => ({ n: "\n", t: "\t", r: "\r", "\\": "\\" })[c]);
}

function readKV(file) {
  const out = {};
  try {
    for (const line of fs.readFileSync(file, "utf8").split("\n")) {
      const i = line.indexOf("=");
      if (i > 0 && !(line.slice(0, i) in out)) out[line.slice(0, i)] = unescapeValue(line.slice(i + 1));
    }
  } catch (_) {}
  return out;
}

let configCache = null;
let configAt = 0;
function config(key) {
  if (!configCache || Date.now() - configAt > 2000) {
    const kv = readKV(CONFIG_FILE);
    configCache = { ...DEFAULTS };
    for (const k of Object.keys(kv)) if (k.startsWith("router.") && kv[k] !== "") configCache[k.slice(7)] = kv[k];
    configAt = Date.now();
  }
  return configCache[key];
}

function configNumber(key) {
  const n = Number(config(key));
  return Number.isFinite(n) && n >= 0 ? n : Number(DEFAULTS[key]);
}

// --------------------------------------------------------------- routes

// key "project\tworktree" -> { key, project, worktree, port, publicPort }
let instances = new Map();
// host -> instance key, and wildcard suffixes ".<host>" -> key
let hosts = new Map();
let wildcards = [];
let refreshing = null;
let lastRefresh = 0;

function childEnv() {
  const env = { ...process.env, PWT_NO_UPDATE_CHECK: "1", PWT_AGENT: "1" };
  // The router may have been started from inside a worktree's shell; its
  // context must not leak into the commands it runs for other worktrees.
  for (const k of ["PWT_PORT", "PWT_WORKTREE", "PWT_WORKTREE_PATH", "PWT_BRANCH", "PWT_TICKET",
    "PWT_PROJECT", "PWT_ARGS", "PWT_BOOT_FILE", "PWT_BG", "PWT_NO_INPUT", "PWT_ROUTER_PORT",
    "PWT_ROUTER_LISTEN", "PWT_PUBLIC_PORT", "PWT_PUBLIC_URL", "PWT_HOST", "PWT_URL", "PWT_HOSTS"]) {
    delete env[k];
  }
  return env;
}

function runPwt(args, timeoutMs) {
  return new Promise((resolve) => {
    let out = "";
    let child;
    try {
      child = spawn(PWT_BIN, args, { cwd: os.homedir(), env: childEnv(), stdio: ["ignore", "pipe", "pipe"] });
    } catch (e) {
      resolve({ code: -1, out: String(e) });
      return;
    }
    const keep = (d) => {
      out += d;
      if (out.length > 16384) out = out.slice(-16384);
    };
    child.stdout.on("data", keep);
    child.stderr.on("data", keep);
    let timer = null;
    if (timeoutMs) timer = setTimeout(() => child.kill("SIGTERM"), timeoutMs);
    child.on("error", (e) => {
      if (timer) clearTimeout(timer);
      resolve({ code: -1, out: out + String(e) });
    });
    child.on("close", (code) => {
      if (timer) clearTimeout(timer);
      resolve({ code: code === null ? -1 : code, out });
    });
  });
}

function refreshRoutes() {
  if (refreshing) return refreshing;
  refreshing = runPwt(["router", "routes", "--porcelain"], 60000).then(({ code, out }) => {
    refreshing = null;
    lastRefresh = Date.now();
    if (code !== 0) {
      log(`routes refresh failed (exit ${code}): ${out.trim().split("\n").pop() || ""}`);
      return;
    }
    const next = new Map();
    const nextHosts = new Map();
    const nextWild = [];
    for (const line of out.split("\n")) {
      const [host, project, worktree, port, alias, , publicPort] = line.split("\t");
      if (!host || !project || !worktree || !Number(port)) continue;
      const key = `${project}\t${worktree}`;
      if (!alias) {
        next.set(key, { key, project, worktree, port: Number(port), publicPort: Number(publicPort) || 0 });
      }
      if (alias === "*") nextWild.push({ suffix: host.slice(1), key });
      else if (!nextHosts.has(host)) nextHosts.set(host, key);
    }
    // Longest suffix first: *.wt.proj.localhost wins over *.proj.localhost
    nextWild.sort((a, b) => b.suffix.length - a.suffix.length);
    instances = next;
    hosts = nextHosts;
    wildcards = nextWild;
    return syncListeners();
  });
  return refreshing;
}

function instanceForHost(hostHeader) {
  if (!hostHeader) return null;
  let host = String(hostHeader).toLowerCase();
  if (host.startsWith("[")) host = host.slice(0, host.indexOf("]") + 1);
  else host = host.replace(/:\d+$/, "");
  host = host.replace(/\.$/, "");
  let key = hosts.get(host);
  if (!key) {
    const w = wildcards.find((c) => host.endsWith(c.suffix) && host.length > c.suffix.length);
    if (w) key = w.key;
  }
  return key ? instances.get(key) || null : null;
}

// ------------------------------------------------------------- activity

// key -> { last (ms), inFlight, routed }
const activity = new Map();
let activityDirty = false;

function act(inst) {
  let a = activity.get(inst.key);
  if (!a) {
    a = { last: Date.now(), inFlight: 0, routed: false };
    activity.set(inst.key, a);
  }
  return a;
}

function begin(inst) {
  const a = act(inst);
  a.inFlight++;
  a.last = Date.now();
  a.routed = true;
  activityDirty = true;
  let done = false;
  return () => {
    if (done) return;
    done = true;
    a.inFlight = Math.max(0, a.inFlight - 1);
    a.last = Date.now();
    activityDirty = true;
  };
}

function writeActivity() {
  if (!activityDirty) return;
  activityDirty = false;
  const lines = [];
  for (const [key, a] of activity) lines.push(`${key}\t${Math.floor(a.last / 1000)}\t${a.inFlight}`);
  const tmp = `${ACTIVITY_FILE}.tmp.${process.pid}`;
  try {
    fs.mkdirSync(ROUTER_DIR, { recursive: true });
    fs.writeFileSync(tmp, lines.join("\n") + (lines.length ? "\n" : ""));
    fs.renameSync(tmp, ACTIVITY_FILE);
  } catch (e) {
    log(`activity write failed: ${e.message}`);
  }
}

// --------------------------------------------------------------- probes

// Which loopback address a server answers on (127.0.0.1 or ::1), or null
function probeOne(host, port) {
  return new Promise((resolve) => {
    const s = net.connect({ host, port });
    const finish = (ok) => {
      s.destroy();
      resolve(ok);
    };
    s.setTimeout(1000, () => finish(false));
    s.once("connect", () => finish(true));
    s.once("error", () => finish(false));
  });
}

async function probe(port) {
  if (await probeOne("127.0.0.1", port)) return "127.0.0.1";
  if (await probeOne("::1", port)) return "::1";
  return null;
}

// ----------------------------------------------------------------- boot

function bootFile(inst, prev) {
  return path.join(PWT_DIR, "state", inst.project, `${inst.worktree}.boot${prev ? ".prev" : ""}.jsonl`);
}

function readJsonl(file) {
  try {
    return fs
      .readFileSync(file, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((l) => {
        try {
          return JSON.parse(l);
        } catch (_) {
          return null;
        }
      })
      .filter(Boolean);
  } catch (_) {
    return [];
  }
}

function tail(file, lines) {
  try {
    const st = fs.statSync(file);
    const len = Math.min(st.size, 16384);
    const fd = fs.openSync(file, "r");
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, st.size - len);
    fs.closeSync(fd);
    return buf.toString("utf8").split("\n").slice(-lines).join("\n");
  } catch (_) {
    return "";
  }
}

// key -> { state: booting|failed, startedAt, error, output, ready: Promise<addr|null> }
const boots = new Map();

function wake(inst) {
  const existing = boots.get(inst.key);
  if (existing && existing.state === "booting") return existing;
  // A failure stays visible for a few seconds before a reload retries
  if (existing && existing.state === "failed" && Date.now() - existing.failedAt < 5000) return existing;

  const b = { state: "booting", startedAt: Date.now(), error: "", output: "" };
  boots.set(inst.key, b);
  const timeoutMs = configNumber("boot_timeout") * 1000;
  const fail = (msg) => {
    if (b.state !== "booting") return;
    b.state = "failed";
    b.error = msg;
    b.failedAt = Date.now();
    log(`wake ${inst.project}/${inst.worktree}: failed: ${msg}`);
  };
  log(`wake ${inst.project}/${inst.worktree}: starting server (port ${inst.port})`);
  runPwt(["--project", inst.project, "server", inst.worktree, "--bg", "--no-input"], timeoutMs).then(({ code, out }) => {
    b.output = out;
    // 4 = already running: another wake (or a human) got there first
    if (code !== 0 && !(code === 4 && /Already running/.test(out))) {
      fail(lastMeaningfulLine(out) || `pwt server exited with ${code}`);
    }
  });
  b.ready = new Promise((resolve) => {
    const tick = async () => {
      const addr = await probe(inst.port);
      if (addr) {
        boots.delete(inst.key);
        log(`wake ${inst.project}/${inst.worktree}: ready after ${Date.now() - b.startedAt}ms`);
        resolve(addr);
        return;
      }
      const lines = readJsonl(bootFile(inst));
      const bootFail = lines.find((l) => l.step === "boot" && l.state === "fail" && l.ts_ms >= b.startedAt - 2000);
      if (bootFail) fail(bootFail.detail || "boot failed");
      if (b.state === "failed") return resolve(null);
      if (Date.now() - b.startedAt > timeoutMs) {
        fail(`not listening on port ${inst.port} after ${configNumber("boot_timeout")}s`);
        return resolve(null);
      }
      setTimeout(tick, 300);
    };
    tick();
  });
  return b;
}

function lastMeaningfulLine(out) {
  const lines = out
    .replace(/\x1b\[[0-9;]*m/g, "")
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
  const err = lines.find((l) => /^Error|cap reached|failed/i.test(l));
  return err || lines.pop() || "";
}

function bootStatus(inst, listening) {
  const b = boots.get(inst.key);
  // Until `pwt server` rotates the file, it still holds the previous boot:
  // the current boot is the one whose "boot start" came after this wake
  const current = readJsonl(bootFile(inst));
  let startIdx = -1;
  current.forEach((l, i) => {
    if (l.step === "boot" && l.state === "start") startIdx = i;
  });
  const fresh = !b || (startIdx >= 0 && (current[startIdx].ts_ms || 0) >= b.startedAt - 1000);
  const lines = fresh ? current.slice(Math.max(startIdx, 0)) : [];
  // ...and that unrotated boot, if it finished, is the best estimate yet
  const unrotated = !fresh && current.some((l) => l.step === "boot" && l.state === "done");
  const prev = unrotated ? current : readJsonl(bootFile(inst, true));
  const prevDur = {};
  for (const l of prev) if (l.state === "done" && Number.isFinite(l.duration_ms)) prevDur[l.step] = l.duration_ms;
  const order = [];
  const steps = {};
  let bootStart = null;
  let logPath = "";
  for (const l of lines) {
    if (l.step === "boot") {
      if (l.state === "start") bootStart = l.ts_ms;
      continue;
    }
    if (!steps[l.step]) {
      steps[l.step] = { step: l.step, state: l.state, duration_ms: null, eta_ms: prevDur[l.step] ?? null, detail: "" };
      order.push(l.step);
    }
    const s = steps[l.step];
    s.state = l.state;
    if (l.state === "start") s.started_ms = l.ts_ms;
    if (Number.isFinite(l.duration_ms)) s.duration_ms = l.duration_ms;
    if (l.detail) s.detail = l.detail;
    const m = /log=(\S+)/.exec(l.detail || "");
    if (m) logPath = m[1];
  }
  const now = Date.now();
  for (const name of order) {
    const s = steps[name];
    if (s.state === "start" && s.started_ms) s.elapsed_ms = now - s.started_ms;
    delete s.started_ms;
  }
  // Steps the last good boot had and this one has not reached yet
  for (const l of prev) {
    if (l.step === "boot" || steps[l.step] || l.state !== "done") continue;
    steps[l.step] = { step: l.step, state: "pending", duration_ms: null, eta_ms: l.duration_ms, detail: "" };
    order.push(l.step);
  }
  let state = listening ? "ready" : "stopped";
  if (!listening && b) state = b.state;
  const startedAt = b ? b.startedAt : bootStart;
  const out = {
    project: inst.project,
    worktree: inst.worktree,
    state,
    elapsed_ms: startedAt && state === "booting" ? now - startedAt : null,
    eta_ms: prevDur.boot ?? null,
    steps: order.map((n) => steps[n]),
    error: b && b.state === "failed" ? b.error : "",
    log_tail: "",
  };
  if (state === "failed" && config("expose_logs") !== "false") {
    out.log_tail = logPath ? tail(logPath, 40) : (b && b.output) || "";
  }
  return out;
}

// ---------------------------------------------------------------- pages

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function wantsHtml(req) {
  return req.method === "GET" && /text\/html/.test(req.headers.accept || "");
}

function sendText(res, status, msg, extra) {
  if (res.headersSent) return res.end();
  res.writeHead(status, { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store", ...(extra || {}) });
  res.end(msg + "\n");
}

function sendJson(res, status, obj) {
  res.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  res.end(JSON.stringify(obj) + "\n");
}

// The page polls /__pwt/boot on its own origin and reloads the original URL
// once the server listens. Without JavaScript the meta refresh retries.
function bootPage(inst, status) {
  const title = `${inst.project} / ${inst.worktree}`;
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<noscript><meta http-equiv="refresh" content="3"></noscript>
<title>Starting ${escapeHtml(title)}</title>
<style>
:root{color-scheme:light dark;--bg:#fafaf9;--fg:#1c1917;--mute:#78716c;--ok:#15803d;--bad:#b91c1c;--line:#e7e5e4}
@media (prefers-color-scheme:dark){:root{--bg:#1c1917;--fg:#f5f5f4;--mute:#a8a29e;--ok:#4ade80;--bad:#f87171;--line:#44403c}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:560px;margin:12vh auto;padding:0 16px}
h1{font-size:18px;font-weight:600;margin:0 0 4px}
p{margin:0 0 20px;color:var(--mute)}
ol{list-style:none;padding:0;margin:0;border-top:1px solid var(--line)}
li{display:flex;gap:12px;padding:8px 0;border-bottom:1px solid var(--line);font-variant-numeric:tabular-nums}
li .n{flex:1}li .t{color:var(--mute)}
li.done .s{color:var(--ok)}li.fail .s{color:var(--bad)}li.pending{color:var(--mute)}
.s{width:1.2em;text-align:center}
pre{overflow:auto;font-size:12px;padding:12px;border:1px solid var(--line);border-radius:6px;max-height:40vh}
.err{color:var(--bad)}
</style></head>
<body><main>
<h1 id="h">Starting ${escapeHtml(title)}</h1>
<p id="sub">The server was asleep. This page reloads when it is ready.</p>
<ol id="steps"></ol>
<div id="fail"></div>
</main>
<script>
const initial = ${JSON.stringify(status).replace(/</g, "\\u003c")};
const fmt = (ms) => ms == null ? "" : (ms < 1000 ? ms + " ms" : (ms / 1000).toFixed(1) + " s");
const icon = {done: "\\u2713", fail: "\\u2717", start: "\\u2026", skip: "\\u2013", pending: "\\u00b7"};
function render(s) {
  if (s.state === "ready") { location.reload(); return; }
  const ol = document.getElementById("steps");
  ol.textContent = "";
  for (const st of s.steps) {
    const li = document.createElement("li");
    li.className = st.state;
    const t = st.state === "done" || st.state === "fail" ? fmt(st.duration_ms)
      : st.state === "start" ? fmt(st.elapsed_ms) + (st.eta_ms != null ? " of ~" + fmt(st.eta_ms) : "")
      : st.eta_ms != null ? "~" + fmt(st.eta_ms) : "";
    li.innerHTML = '<span class="s"></span><span class="n"></span><span class="t"></span>';
    li.children[0].textContent = icon[st.state] || "";
    li.children[1].textContent = st.step;
    li.children[2].textContent = t;
    ol.appendChild(li);
  }
  const sub = document.getElementById("sub");
  if (s.state === "booting") {
    sub.textContent = "Booting for " + fmt(s.elapsed_ms) + (s.eta_ms != null ? ", usually ~" + fmt(s.eta_ms) : "") + ". This page reloads when it is ready.";
  }
  if (s.state === "failed") {
    document.getElementById("h").textContent = "Could not start " + s.project + " / " + s.worktree;
    sub.className = "err";
    sub.textContent = s.error || "The boot failed.";
    const f = document.getElementById("fail");
    f.textContent = "";
    if (s.log_tail) { const pre = document.createElement("pre"); pre.textContent = s.log_tail; f.appendChild(pre); }
    return false;
  }
  return true;
}
async function poll() {
  try {
    const r = await fetch("/__pwt/boot", {cache: "no-store"});
    if (render(await r.json()) === false) { setTimeout(poll, 5000); return; }
  } catch (_) {}
  setTimeout(poll, 1000);
}
if (render(initial) !== false) setTimeout(poll, 1000); else setTimeout(poll, 5000);
</script>
</body></html>
`;
}

// ---------------------------------------------------------------- proxy

const agent = new http.Agent({ keepAlive: true, maxSockets: 256 });
const HOP = ["connection", "keep-alive", "proxy-connection", "upgrade"];

function forwardedHeaders(req, publicPort) {
  const h = { ...req.headers };
  for (const k of HOP) delete h[k];
  const remote = req.socket.remoteAddress || "";
  h["x-forwarded-for"] = h["x-forwarded-for"] ? `${h["x-forwarded-for"]}, ${remote}` : remote;
  if (!h["x-forwarded-host"] && req.headers.host) h["x-forwarded-host"] = req.headers.host;
  if (!h["x-forwarded-proto"]) h["x-forwarded-proto"] = "http";
  if (!h["x-forwarded-port"] && publicPort) h["x-forwarded-port"] = String(publicPort);
  return h;
}

function proxyHttp(inst, addr, req, res, done) {
  const preq = http.request(
    { host: addr, port: inst.port, method: req.method, path: req.url, headers: forwardedHeaders(req, inst.publicPort), agent },
    (pres) => {
      const headers = { ...pres.headers };
      delete headers.connection;
      delete headers["keep-alive"];
      res.writeHead(pres.statusCode || 502, pres.statusMessage, headers);
      pres.pipe(res);
      pres.on("error", () => res.destroy());
    }
  );
  preq.on("error", (e) => {
    sendText(res, 502, `pwt router: ${inst.project}/${inst.worktree} on port ${inst.port} failed: ${e.message}`);
    done();
  });
  req.pipe(preq);
  res.on("close", () => {
    if (!res.writableFinished) preq.destroy();
    done();
  });
}

async function serveInstance(inst, req, res) {
  if (req.url === "/__pwt/boot" || req.url.startsWith("/__pwt/boot?")) {
    sendJson(res, 200, bootStatus(inst, Boolean(await probe(inst.port))));
    return;
  }
  const done = begin(inst);
  let addr = await probe(inst.port);
  if (!addr) {
    const b = wake(inst);
    if (wantsHtml(req)) {
      const page = bootPage(inst, bootStatus(inst, false));
      res.writeHead(503, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "Retry-After": "2" });
      res.end(page);
      done();
      return;
    }
    const holdMs = configNumber("hold_seconds") * 1000;
    addr = await Promise.race([b.ready, new Promise((r) => setTimeout(() => r(null), holdMs))]);
    if (!addr) {
      const failed = b.state === "failed";
      sendText(
        res,
        503,
        failed
          ? `pwt router: ${inst.project}/${inst.worktree} failed to start: ${b.error}`
          : `pwt router: ${inst.project}/${inst.worktree} is still starting`,
        { "Retry-After": failed ? "30" : "5" }
      );
      done();
      return;
    }
  }
  proxyHttp(inst, addr, req, res, done);
}

async function serveUpgrade(inst, req, socket, head) {
  socket.on("error", () => socket.destroy());
  const done = begin(inst);
  socket.on("close", done);
  let addr = await probe(inst.port);
  if (!addr) {
    const b = wake(inst);
    const holdMs = configNumber("hold_seconds") * 1000;
    addr = await Promise.race([b.ready, new Promise((r) => setTimeout(() => r(null), holdMs))]);
    if (!addr) {
      socket.end("HTTP/1.1 503 Service Unavailable\r\nRetry-After: 5\r\nConnection: close\r\n\r\n");
      return;
    }
  }
  const backend = net.connect({ host: addr, port: inst.port }, () => {
    const h = forwardedHeaders(req, inst.publicPort);
    h.connection = "Upgrade";
    h.upgrade = req.headers.upgrade;
    let raw = `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`;
    for (const [k, v] of Object.entries(h)) {
      for (const one of Array.isArray(v) ? v : [v]) raw += `${k}: ${one}\r\n`;
    }
    backend.write(raw + "\r\n");
    if (head && head.length) backend.write(head);
    socket.pipe(backend).pipe(socket);
  });
  backend.on("error", () => socket.destroy());
  backend.on("close", () => socket.destroy());
  socket.on("close", () => backend.destroy());
}

// ------------------------------------------------------------ listeners

const listenAddrs = () =>
  String(process.env.PWT_ROUTER_LISTEN || config("listen"))
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

// publicPort -> { key, servers: [http.Server], error }
const portListeners = new Map();

function makeServer(resolveInst) {
  const server = http.createServer(async (req, res) => {
    try {
      const inst = await resolveInst(req);
      if (!inst) return; // resolveInst answered already
      await serveInstance(inst, req, res);
    } catch (e) {
      log(`request error: ${e.stack || e}`);
      sendText(res, 500, "pwt router: internal error");
    }
  });
  server.on("upgrade", async (req, socket, head) => {
    try {
      const inst = await resolveInst(req, socket);
      if (!inst) return;
      await serveUpgrade(inst, req, socket, head);
    } catch (e) {
      log(`upgrade error: ${e.stack || e}`);
      socket.destroy();
    }
  });
  server.keepAliveTimeout = 5000;
  return server;
}

// Bind one http.Server per address. A missing ::1 (containers without IPv6)
// is fine; failing every address is reported to the caller.
function bindAll(port, resolveInst) {
  return new Promise((resolve) => {
    const addrs = listenAddrs();
    const servers = [];
    const errors = [];
    let pending = addrs.length;
    for (const a of addrs) {
      const s = makeServer(resolveInst);
      s.once("error", (e) => {
        errors.push(`${a}: ${e.code || e.message}`);
        if (--pending === 0) resolve({ servers, errors });
      });
      s.listen(port, a, () => {
        servers.push(s);
        if (--pending === 0) resolve({ servers, errors });
      });
    }
  });
}

// Resolves once every new public port has bound (or failed to)
function syncListeners() {
  const binds = [];
  const wanted = new Map();
  for (const inst of instances.values()) if (inst.publicPort) wanted.set(inst.publicPort, inst.key);
  for (const [port, l] of portListeners) {
    if (wanted.get(port) !== l.key) {
      for (const s of l.servers) s.close();
      portListeners.delete(port);
    }
  }
  for (const [port, key] of wanted) {
    const l = portListeners.get(port);
    if (l && (l.servers.length || l.binding || Date.now() - l.failedAt < REFRESH_MS)) continue;
    const entry = { key, servers: [], binding: true, error: "" };
    portListeners.set(port, entry);
    const bound = bindAll(port, async (req, socket) => {
      const inst = instances.get(key);
      if (inst) return inst;
      if (socket) socket.destroy();
      return null;
    }).then(({ servers, errors }) => {
      entry.binding = false;
      entry.servers = servers;
      if (!servers.length) {
        entry.error = errors.join(", ");
        entry.failedAt = Date.now();
        const inst = instances.get(key);
        log(`port ${port} (${inst ? `${inst.project}/${inst.worktree}` : key}): cannot listen: ${entry.error}`);
      }
    });
    binds.push(bound);
  }
  return Promise.all(binds);
}

// The router's own port: status page, and Host routing when enabled
async function resolveMain(req, socketOrRes) {
  if (config("host_routing") === "true") {
    let inst = instanceForHost(req.headers.host);
    if (!inst && Date.now() - lastRefresh > 3000) {
      await refreshRoutes();
      inst = instanceForHost(req.headers.host);
    }
    if (inst) return inst;
  }
  return null;
}

function statusPayload() {
  const list = [];
  for (const inst of instances.values()) {
    const a = activity.get(inst.key);
    const l = portListeners.get(inst.publicPort);
    list.push({
      project: inst.project,
      worktree: inst.worktree,
      port: inst.port,
      public_port: inst.publicPort || null,
      listening_public: Boolean(l && l.servers.length),
      error: (l && l.error) || null,
      booting: boots.has(inst.key) && boots.get(inst.key).state === "booting",
      last_request_epoch: a && a.routed ? Math.floor(a.last / 1000) : null,
      in_flight: a ? a.inFlight : 0,
    });
  }
  return { pid: process.pid, instances: list };
}

async function startMain() {
  const port = Number(process.env.PWT_ROUTER_PORT || config("port"));
  const { servers, errors } = await bindAll(port, async (req, socket) => {
    const inst = await resolveMain(req);
    if (inst) return inst;
    if (socket) {
      socket.end("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n");
      return null;
    }
    return null;
  });
  if (!servers.length) {
    console.error(`[pwt router] cannot listen on port ${port}: ${errors.join(", ")}`);
    process.exit(1);
  }
  // Requests the resolver did not claim: status page / JSON / 404
  for (const s of servers) {
    s.removeAllListeners("request");
    s.on("request", async (req, res) => {
      try {
        const inst = await resolveMain(req);
        if (inst) return serveInstance(inst, req, res);
        if (req.url === "/__pwt/status") return sendJson(res, 200, statusPayload());
        if (config("host_routing") === "true" && req.headers.host && !/^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(req.headers.host)) {
          return sendText(res, 404, `pwt router: no worktree answers to ${req.headers.host}`);
        }
        const rows = statusPayload()
          .instances.map((i) => `${String(i.public_port || "-").padEnd(7)} ${i.project}/${i.worktree} -> ${i.port}${i.error ? `  (${i.error})` : ""}`)
          .join("\n");
        sendText(res, 200, `pwt router (pid ${process.pid})\n\n${rows || "(no worktrees)"}`);
      } catch (e) {
        log(`request error: ${e.stack || e}`);
        sendText(res, 500, "pwt router: internal error");
      }
    });
  }
  mainServers = servers;
  log(`listening on ${listenAddrs().join(",")} port ${port}`);
}

let mainServers = [];

// ------------------------------------------------------------- idle stop

const stopping = new Set();

async function idleTick() {
  const idleMin = configNumber("idle_minutes");
  if (!(idleMin > 0)) return;
  const now = Date.now();
  for (const inst of instances.values()) {
    if (inst.worktree === "@") continue;
    const a = activity.get(inst.key);
    // Only servers people reach through the router: one used directly on
    // its own port (an agent's test run) shows no traffic here.
    if (!a || !a.routed || a.inFlight > 0) continue;
    if (now - a.last < idleMin * 60000) continue;
    if (stopping.has(inst.key) || boots.has(inst.key)) continue;
    if (!(await probe(inst.port))) {
      a.routed = false;
      continue;
    }
    stopping.add(inst.key);
    runPwt(["--project", inst.project, "servers", "stop", inst.worktree, "--idle"], 60000).then(({ code, out }) => {
      stopping.delete(inst.key);
      if (code === 0) {
        log(`idle stop ${inst.project}/${inst.worktree} after ${idleMin} min`);
        a.routed = false;
      } else if (code === 3) {
        // Not a pwt job (a foreground server): leave it alone for good
        a.routed = false;
      } else {
        // Busy (exit 4) or failed: look again after another idle window
        a.last = Date.now();
        log(`idle stop ${inst.project}/${inst.worktree} skipped (exit ${code}): ${lastMeaningfulLine(out)}`);
      }
    });
  }
}

// ------------------------------------------------------------------ main

function restoreActivity() {
  try {
    for (const line of fs.readFileSync(ACTIVITY_FILE, "utf8").split("\n")) {
      const [project, worktree, last] = line.split("\t");
      if (!project || !worktree) continue;
      activity.set(`${project}\t${worktree}`, { last: Number(last) * 1000 || Date.now(), inFlight: 0, routed: true });
    }
  } catch (_) {}
}

function shutdown() {
  activityDirty = true;
  writeActivity();
  for (const s of mainServers) s.close();
  for (const l of portListeners.values()) for (const s of l.servers) s.close();
  process.exit(0);
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
process.on("SIGHUP", () => refreshRoutes());

(async () => {
  restoreActivity();
  await startMain();
  await refreshRoutes();
  // `pwt router up` returns once this exists: every public port is open
  try {
    fs.writeFileSync(path.join(ROUTER_DIR, "ready"), `${process.pid}\n`);
  } catch (_) {}
  setInterval(refreshRoutes, REFRESH_MS).unref();
  setInterval(writeActivity, 2000).unref();
  setInterval(() => idleTick().catch((e) => log(`idle tick: ${e.message}`)), IDLE_TICK_MS);
})();
