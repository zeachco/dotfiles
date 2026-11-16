#!/usr/bin/env node
/**
 * autorouter -- a dynamic model alias in front of the local llama.cpp router.
 *
 * The llama.cpp router (:7070, see ../archlinux/README.md) serves concrete model
 * ids and REFUSES a request for a model that is not resident (--no-models-autoload).
 * Every harness client (pi, opencode) must therefore track which model is loaded
 * and re-resolve after a swap or an evict. This proxy adds one virtual model,
 * `auto`, that resolves at request time to a model the box can actually serve right
 * now, so a client points at ONE endpoint and reads the routed model's live stats
 * (context window, modalities, reasoning) from GET /v1/models:
 *
 *   harness --(model: "auto")--> autorouter :7080 --(model: <target>)--> router :7070
 *
 * The `auto` card in GET /v1/models MIRRORS the router's own card shape for the
 * current target (status.value + status.args + architecture + context_length), so
 * bin/llamacpp-sync and pi's llamacpp-discover extension consume it unchanged:
 * they derive the per-slot context from status.args and the input modalities from
 * architecture, and the extension's self-heal (load-on-404) works through it too.
 *
 * Routing policy (observe() / route()):
 *   1. a candidate is a chat model the router reports `loaded` or `sleeping`
 *      (a sleeping child wakes on the next request; gemma-4 router models are
 *      excluded, they are not served to clients);
 *   2. both mains candidates -> FREE GTT MEMORY picks:
 *      free >= AUTOROUTER_SWITCH_GIB -> AUTOROUTER_MAIN, else AUTOROUTER_FAST;
 *   3. exactly one main resident -> that one;
 *   4. only other models resident -> the one with the largest context;
 *   5. nothing resident -> load AUTOROUTER_DEFAULT on the router and wait for it.
 *
 * Everything else is a transparent proxy: a concrete router model id in the
 * request's `model` field forwards unchanged, and any other path
 * (POST /models/load, /props, ...) passes through untouched. For `auto`
 * requests the response's `model` is rewritten back to `auto` (JSON and SSE
 * alike), and the routed target goes in the `x-autorouter-target` response
 * header, so a client attributes tokens, usage and errors to the alias.
 *
 * Endpoints:
 *   GET  /v1/models      the single `auto` card (router-shaped) + its routing block
 *   GET  /v1/routing     the live decision: candidates, free GTT, loadavg, reason
 *   GET  /health         liveness, plus whether the upstream router answers
 *   POST /models/load    {model: "auto"} -> ensure a candidate (loads the default
 *                        when none); any other id forwards to the router
 *   POST /v1/chat/completions, /v1/completions -> routed (see policy)
 *   *    anything else  -> raw pass-through
 *
 * Config (env, all optional -- the unit file sets them):
 *   AUTOROUTER_HOST        127.0.0.1       # loopback only; the router stays LAN-facing
 *   AUTOROUTER_PORT        7080
 *   AUTOROUTER_UPSTREAM    http://127.0.0.1:7070
 *   AUTOROUTER_DEFAULT     Qwen3.8-Flash-Next  # loaded when nothing is resident
 *   AUTOROUTER_MAIN        qwen3.8               # preferred while memory is free
 *   AUTOROUTER_FAST        Qwen3.8-Flash-Next    # preferred under memory pressure
 *   AUTOROUTER_SWITCH_GIB  48                    # free GTT at which MAIN wins
 *
 * No dependencies: node:http + global fetch only. One log line per request on
 * stderr (the journal picks it up).
 */

import http from "node:http";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { Readable, Transform } from "node:stream";

const HOST = process.env.AUTOROUTER_HOST || "127.0.0.1";
const PORT = Number(process.env.AUTOROUTER_PORT || 7080);
const UPSTREAM = (process.env.AUTOROUTER_UPSTREAM || "http://127.0.0.1:7070").replace(/\/+$/, "");
const DEFAULT_MODEL = process.env.AUTOROUTER_DEFAULT || "Qwen3.8-Flash-Next";
const MAIN_MODEL = process.env.AUTOROUTER_MAIN || "qwen3.8";
const FAST_MODEL = process.env.AUTOROUTER_FAST || "Qwen3.8-Flash-Next";
const SWITCH_GIB = Number(process.env.AUTOROUTER_SWITCH_GIB || 48);

const GIB = 1 << 30;
const MODELS_CACHE_MS = 3000; // router state changes slowly; do not hit it per request
const LOAD_WAIT_MS = 120_000;
const LOAD_POLL_MS = 2000;
const REQUEST_TIMEOUT_MS = 35 * 60_000; // the router's own -to is 3600

// ---------------------------------------------------------------------------
// upstream state

/** @type {{at: number, value: Array<object>}} */
let modelsCache = { at: 0, value: [] };

async function upstreamModels(force = false) {
  const now = Date.now();
  if (!force && modelsCache.value.length > 0 && now - modelsCache.at < MODELS_CACHE_MS) {
    return modelsCache.value;
  }
  const res = await fetch(`${UPSTREAM}/v1/models`, { signal: AbortSignal.timeout(5000) });
  if (!res.ok) throw new Error(`upstream /v1/models HTTP ${res.status}`);
  const payload = await res.json();
  const value = (payload.data || []).filter((m) => m && typeof m.id === "string");
  modelsCache = { at: Date.now(), value };
  return value;
}

/** Free GTT memory in GiB (amdgpu sysfs), or undefined when unreadable. */
function freeGib() {
  const drm = "/sys/class/drm";
  if (!existsSync(drm)) return undefined;
  for (const card of readdirSync(drm)) {
    const base = join(drm, card, "device");
    try {
      const total = Number(readFileSync(join(base, "mem_info_gtt_total"), "utf8").trim());
      const used = Number(readFileSync(join(base, "mem_info_gtt_used"), "utf8").trim());
      if (total > 0) return (total - used) / GIB;
    } catch {
      // not a card with GTT stats; try the next
    }
  }
  return undefined;
}

function loadAvg() {
  try {
    return readFileSync("/proc/loadavg", "utf8").trim().split(/\s+/).slice(0, 3).join(" ");
  } catch {
    return null;
  }
}

/**
 * The context one conversation actually gets, not the pool size -- the same
 * rule as per_slot_context in bin/llamacpp-sync and perSlotContext in pi's
 * llamacpp-discover extension, so all three consumers agree on a card:
 *   --ctx-size, capped by --kv-unified-per-slot, then (without --kv-unified)
 *   split across the --parallel children.
 */
function perSlotContext(args) {
  if (!Array.isArray(args)) return undefined;
  const find = (flag) => {
    const idx = args.findIndex((a) => typeof a === "string" && (a === flag || a.startsWith(flag + "=")));
    if (idx < 0) return undefined;
    const a = args[idx];
    return a.includes("=") ? a.slice(a.indexOf("=") + 1) : idx + 1 < args.length ? args[idx + 1] : undefined;
  };
  const asInt = (v) => (typeof v === "string" && /^\d+$/.test(v) ? Number(v) : undefined);
  let ctx = asInt(find("--ctx-size"));
  if (ctx === undefined) return undefined;
  const cap = asInt(find("--kv-unified-per-slot"));
  if (cap) ctx = Math.min(ctx, cap);
  if (args.includes("--kv-unified") || args.includes("-kvu")) return ctx;
  const n = asInt(find("--parallel")) ?? asInt(find("-np"));
  return n ? Math.max(1, Math.floor(ctx / n)) : ctx;
}

function ctxOf(card) {
  return perSlotContext(card?.status?.args) ?? card?.context_length ?? 0;
}

function isChatCard(card) {
  const out = card?.architecture?.output_modalities;
  return Array.isArray(out) && !out.includes("decisions");
}

/** Ask the router to load a model. Non-2xx is NOT an error: an already-loading
 *  or already-resident model still ends up loaded; the caller polls. */
async function requestLoad(id) {
  try {
    const res = await fetch(`${UPSTREAM}/models/load`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ model: id }),
      signal: AbortSignal.timeout(10_000),
    });
    await res.text().catch(() => {});
  } catch (err) {
    log("load", id, `request failed: ${err.message}`);
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/**
 * The routing decision WITHOUT side effects: what is resident and which model
 * `auto` would use right now. Never loads anything.
 */
async function observe() {
  const models = await upstreamModels();
  const byId = new Map(models.map((m) => [m.id, m]));
  const candidates = models.filter((m) => {
    if (!isChatCard(m) || /^gemma-4-/i.test(m.id)) return false;
    const s = m.status?.value;
    return s === "loaded" || s === "sleeping";
  });
  const resident = (id) => {
    const s = byId.get(id)?.status?.value;
    return s === "loaded" || s === "sleeping";
  };
  const free = freeGib();
  const report = {
    upstream: UPSTREAM,
    candidates: candidates.map((c) => ({ id: c.id, status: c.status?.value, ctx: ctxOf(c) || null })),
    free_gib: free === undefined ? null : +free.toFixed(1),
    loadavg: loadAvg(),
  };

  if (resident(MAIN_MODEL) && resident(FAST_MODEL)) {
    const useMain = free === undefined || free >= SWITCH_GIB;
    const target = useMain ? MAIN_MODEL : FAST_MODEL;
    return { ...report, target, card: byId.get(target),
      reason: `both mains resident; free GTT ${free === undefined ? "?" : `${free.toFixed(0)} GiB`}` +
        ` ${useMain ? ">=" : "<"} ${SWITCH_GIB} GiB -> ${target}` };
  }
  if (resident(MAIN_MODEL)) return { ...report, target: MAIN_MODEL, card: byId.get(MAIN_MODEL), reason: `${MAIN_MODEL} resident` };
  if (resident(FAST_MODEL)) return { ...report, target: FAST_MODEL, card: byId.get(FAST_MODEL), reason: `${FAST_MODEL} resident` };
  if (candidates.length > 0) {
    const best = candidates.reduce((a, b) => (ctxOf(b) >= ctxOf(a) ? b : a));
    return { ...report, target: best.id, card: best, reason: `no main resident; largest context among ${candidates.length} resident` };
  }
  return { ...report, target: DEFAULT_MODEL, card: byId.get(DEFAULT_MODEL) ?? null, reason: `nothing resident; next request loads ${DEFAULT_MODEL}` };
}

/**
 * The routing decision WITH the last-resort side effect: when nothing is
 * resident, load AUTOROUTER_DEFAULT on the router and wait for it.
 * Throws HttpError(503) when the load does not come up in time.
 */
async function route() {
  const obs = await observe();
  if (obs.candidates.length > 0) return obs;
  await requestLoad(DEFAULT_MODEL);
  const deadline = Date.now() + LOAD_WAIT_MS;
  while (Date.now() < deadline) {
    await sleep(LOAD_POLL_MS);
    const models = await upstreamModels(true);
    const card = models.find((m) => m.id === DEFAULT_MODEL);
    const s = card?.status?.value;
    if (s === "loaded" || s === "sleeping") {
      return { ...obs, target: DEFAULT_MODEL, card, reason: `nothing resident; loaded ${DEFAULT_MODEL}` };
    }
    if (s === "failed") {
      throw new HttpError(503, `${DEFAULT_MODEL} failed to load on the router; check: los-load ${DEFAULT_MODEL}`);
    }
  }
  throw new HttpError(503, `timed out waiting for ${DEFAULT_MODEL} to load; check: los-load ${DEFAULT_MODEL}`);
}

/** The router-shaped card GET /v1/models serves, mirroring the current target. */
function autoCard(decision) {
  const card = decision.card;
  const status = card?.status?.value ?? "unloaded";
  return {
    id: "auto",
    name: `Auto Router (${UPSTREAM})`,
    aliases: [],
    tags: ["autorouter"],
    object: "model",
    owned_by: "autorouter",
    created: Math.floor(Date.now() / 1000),
    status: { value: status, args: card?.status?.args ?? [], preset: card?.status?.preset ?? "" },
    architecture: card?.architecture ?? { input_modalities: ["text"], output_modalities: ["text"] },
    context_length: perSlotContext(card?.status?.args) ?? card?.context_length ?? null,
    routing: {
      target: decision.target,
      reason: decision.reason,
      free_gib: decision.free_gib,
      loadavg: decision.loadavg,
      candidates: decision.candidates,
      config: { default: DEFAULT_MODEL, main: MAIN_MODEL, fast: FAST_MODEL, switch_gib: SWITCH_GIB },
    },
  };
}

// ---------------------------------------------------------------------------
// http plumbing

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (c) => {
      size += c.length;
      if (size > 256 * 1024 * 1024) {
        reject(new HttpError(413, "request body too large"));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

function json(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, { "content-type": "application/json", "content-length": Buffer.byteLength(body) });
  res.end(body);
}

function fail(res, err) {
  if (res.headersSent) { res.end(); return; }
  json(res, err.status || 502, { error: { message: err.message, type: "auto_router_error" } });
}

function log(method, path, extra) {
  console.error(`auto-router ${method} ${path} ${extra}`.trimEnd());
}

/** Rewrite the `model` field of one SSE line (non-data lines pass through). */
function rewriteSseLine(line, alias) {
  if (!line.startsWith("data:")) return line;
  const payload = line.slice(5).trimStart();
  if (payload === "[DONE]") return line;
  try {
    const obj = JSON.parse(payload);
    if (obj && typeof obj === "object") {
      obj.model = alias;
      return "data: " + JSON.stringify(obj);
    }
  } catch {
    // not JSON (should not happen); pass the line through untouched
  }
  return line;
}

/** Pipe an upstream body into `res`, rewriting `model` in SSE data lines when `alias` is set. */
function pipeUpstream(res, upstream, alias) {
  if (alias) {
    const t = new Transform({
      transform(chunk, _enc, cb) {
        try {
          this.buf += chunk.toString("utf8");
          let idx;
          while ((idx = this.buf.indexOf("\n")) >= 0) {
            const line = this.buf.slice(0, idx);
            this.buf = this.buf.slice(idx + 1);
            this.push(rewriteSseLine(line, alias) + "\n");
          }
        } catch (err) {
          cb(err);
          return;
        }
        cb();
      },
      flush(cb) {
        try {
          if (this.buf.length > 0) {
            this.push(rewriteSseLine(this.buf, alias));
            this.buf = "";
          }
        } catch (err) {
          cb(err);
          return;
        }
        cb();
      },
    });
    t.buf = "";
    Readable.fromWeb(upstream.body).pipe(t).pipe(res);
    res.on("close", () => upstream.body?.cancel().catch(() => {}));
    return;
  }
  Readable.fromWeb(upstream.body).pipe(res);
}

/**
 * @param {null | {alias: string, target: string}} rewrite
 *   alias  -- value written into the response's `model` field ("auto")
 *   target -- the model that actually answered (response header, logs)
 */
async function forward(req, res, path, body, rewrite) {
  const upstream = await fetch(`${UPSTREAM}${path}`, {
    method: req.method,
    headers: {
      "content-type": req.headers["content-type"] || "application/json",
      accept: req.headers["accept"] || "application/json",
      ...(req.headers["authorization"] ? { authorization: req.headers["authorization"] } : {}),
    },
    body: body === undefined ? undefined : body,
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  res.writeHead(upstream.status, {
    "content-type": upstream.headers.get("content-type") || "application/octet-stream",
    ...(rewrite ? { "x-autorouter-target": rewrite.target } : {}),
  });
  // alias: null means "header only, leave the body alone" (concrete passthrough)
  if (rewrite?.alias && /text\/event-stream/i.test(upstream.headers.get("content-type") || "")) {
    pipeUpstream(res, upstream, rewrite.alias);
    return;
  }
  if (rewrite?.alias && upstream.status === 200) {
    // non-stream JSON: rewrite the model field once
    const text = await upstream.text();
    try {
      const obj = JSON.parse(text);
      if (obj && typeof obj === "object" && !Array.isArray(obj)) obj.model = rewrite.alias;
      res.end(JSON.stringify(obj));
      return;
    } catch {
      res.end(text);
      return;
    }
  }
  if (upstream.body) {
    Readable.fromWeb(upstream.body).pipe(res);
  } else {
    res.end();
  }
}

// ---------------------------------------------------------------------------
// endpoints

const server = http.createServer(async (req, res) => {
  const started = Date.now();
  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  const path = url.pathname;
  const done = (extra) => log(req.method, path, `${extra} ${res.statusCode} ${Date.now() - started}ms`);

  try {
    // ---- the alias card -----------------------------------------------------
    if (req.method === "GET" && (path === "/v1/models" || path === "/models")) {
      let decision;
      try {
        decision = await observe();
      } catch (err) {
        log(req.method, path, `upstream down: ${err.message} 502`);
        return json(res, 502, { error: { message: `auto router: upstream ${UPSTREAM} unreachable (${err.message})`, type: "auto_router_error" } });
      }
      json(res, 200, { object: "list", data: [autoCard(decision)] });
      return done(`target=${decision.target}`);
    }

    // ---- the live decision ----------------------------------------------------
    if (req.method === "GET" && (path === "/v1/routing" || path === "/routing")) {
      const decision = await observe();
      json(res, 200, { ...decision, config: { default: DEFAULT_MODEL, main: MAIN_MODEL, fast: FAST_MODEL, switch_gib: SWITCH_GIB } });
      return done(`target=${decision.target}`);
    }

    // ---- liveness ---------------------------------------------------------------
    if (req.method === "GET" && path === "/health") {
      const up = await fetch(`${UPSTREAM}/health`, { signal: AbortSignal.timeout(2000) }).then((r) => r.ok).catch(() => false);
      return json(res, up ? 200 : 503, { status: up ? "ok" : "degraded", upstream: UPSTREAM, upstream_healthy: up });
    }

    // ---- model load (the harness self-heal calls this) --------------------------
    if (req.method === "POST" && path === "/models/load") {
      const raw = await readBody(req);
      let parsed = {};
      try { parsed = JSON.parse(raw.toString("utf8") || "{}"); } catch { /* keep {} */ }
      const id = typeof parsed.model === "string" ? parsed.model : "auto";
      if (id !== "auto") {
        // concrete model: pure pass-through to the router
        await forward(req, res, "/models/load", raw.toString("utf8"), { alias: null, target: id });
        return done(`model=${id}`);
      }
      const decision = await observe();
      if (decision.candidates.length > 0) {
        return json(res, 200, { model: decision.target, status: decision.card?.status?.value ?? "loaded", action: "already-resident", reason: decision.reason });
      }
      await requestLoad(DEFAULT_MODEL);
      log("load", "auto", `loading ${DEFAULT_MODEL} 202`);
      return json(res, 202, { model: DEFAULT_MODEL, status: "loading", action: "load-requested" });
    }

    // ---- generation: route `auto`, pass concrete ids through --------------------
    if (req.method === "POST" && (path === "/v1/chat/completions" || path === "/v1/completions")) {
      const raw = await readBody(req);
      let parsed;
      try {
        parsed = JSON.parse(raw.toString("utf8"));
      } catch {
        return json(res, 400, { error: { message: "request body is not JSON", type: "invalid_request_error" } });
      }
      const alias = typeof parsed.model === "string" ? parsed.model : null;
      if (alias === "auto") {
        const decision = await route();
        parsed.model = decision.target;
        await forward(req, res, path, JSON.stringify(parsed), { alias: "auto", target: decision.target });
        return done(`model=auto->${decision.target}`);
      }
      const models = await upstreamModels();
      if (!models.some((m) => m.id === alias)) {
        return json(res, 404, {
          error: {
            message: `unknown model '${alias}'; the auto router serves 'auto' plus every model of ${UPSTREAM}`,
            type: "invalid_request_error",
          },
        });
      }
      await forward(req, res, path, raw.toString("utf8"), { alias: null, target: alias });
      return done(`model=${alias} passthrough`);
    }

    // ---- everything else: raw pass-through ---------------------------------------
    const raw = await readBody(req);
    await forward(req, res, path, raw.length > 0 ? raw.toString("utf8") : undefined, null);
    return done("passthrough");
  } catch (err) {
    log(req.method, path, `error: ${err.message}`);
    return fail(res, err);
  }
});

server.listen(PORT, HOST, async () => {
  console.error(
    `auto-router listening on http://${HOST}:${PORT} (upstream ${UPSTREAM}; ` +
    `default=${DEFAULT_MODEL} main=${MAIN_MODEL} fast=${FAST_MODEL} switch=${SWITCH_GIB} GiB)`
  );
  try {
    const up = await fetch(`${UPSTREAM}/health`, { signal: AbortSignal.timeout(2000) }).then((r) => r.ok).catch(() => false);
    console.error(`auto-router upstream ${UPSTREAM} ${up ? "healthy" : "NOT reachable (it may still be starting)"}`);
  } catch {
    console.error("auto-router upstream health check failed");
  }
});
