import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

import type { Plugin } from "@opencode-ai/plugin"

// Every provider whose id starts with this is discovered from its own baseURL. The
// light tier (:7070) is the router that autoloads every model in the models directory,
// so its /v1/models IS the catalogue -- including models that are not resident, since
// the router reports unloaded ones too. Asking loads nothing, on any tier.
const PROVIDER_PREFIX = "llamacpp"
const FETCH_TIMEOUT_MS = 5_000
const DEFAULT_CONTEXT = 131072
const DEFAULT_OUTPUT = 16384
const REASONING_HINT = /(qwen3|deepseek|glm-4|gpt-oss|ministral|mistral|kimi)/i

// A machine with a models directory IS a router box and serves the weights itself, so
// every llamacpp* endpoint is on loopback. The configured host is the name of the OTHER
// box (oli-llms.local), which from here resolves to something else entirely or, as on
// the mac, to nothing -- so on a router box it has to be rewritten or the client reaches
// no router at all. Only the host moves; port and path stay, so the tier a provider
// points at is unchanged.
const LOCAL_MODELS_DIR = join(homedir(), "models")
const LOOPBACK = "127.0.0.1"

function resolveBaseURL(baseURL: string): string {
  if (!existsSync(LOCAL_MODELS_DIR)) return baseURL
  try {
    const url = new URL(baseURL)
    if (url.hostname === LOOPBACK || url.hostname === "localhost") return baseURL
    url.hostname = LOOPBACK
    return url.toString()
  } catch {
    return baseURL
  }
}

type JsonObject = Record<string, unknown>
type ModelEntry = {
  name?: string
  attachment?: boolean
  reasoning?: boolean
  tool_call?: boolean
  limit?: { context: number; output: number }
  [key: string]: unknown
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function modelsURL(baseURL: string): URL {
  return new URL("models", baseURL.endsWith("/") ? baseURL : `${baseURL}/`)
}

function argValue(args: readonly unknown[], flag: string): string | undefined {
  const i = args.indexOf(flag)
  const value = i === -1 ? undefined : args[i + 1]
  return typeof value === "string" ? value : undefined
}

/** The context ONE conversation gets, not the size of the whole KV pool.
 *
 * --ctx-size is the pool; without --kv-unified the router splits it across --parallel
 * slots and llama.cpp caps a slot at ctx/np. Advertising the pool overstates it by a
 * factor of np, and opencode then fails mid-conversation with a context overflow
 * instead of refusing cleanly up front. Mirrors per_slot_context in bin/llamacpp-sync. */
function perSlotContext(args: readonly unknown[]): number | undefined {
  const ctx = Number(argValue(args, "--ctx-size"))
  if (!Number.isInteger(ctx) || ctx <= 0) return undefined
  if (args.includes("--kv-unified") || args.includes("-kvu")) return ctx
  const parallel = Number(argValue(args, "--parallel") ?? argValue(args, "-np"))
  return Number.isInteger(parallel) && parallel > 0 ? Math.floor(ctx / parallel) : ctx
}

/** One model entry, router facts filled in, anything hand-written in the config kept.
 *
 * The config is still where tuning lives (display name, tool_call off for a small model
 * that answers in prose, cost) -- this only owns what the router actually knows. */
function buildModel(live: JsonObject, existing: ModelEntry | undefined): ModelEntry {
  const ex: ModelEntry = isObject(existing) ? { ...existing } : {}
  const status = isObject(live.status) ? live.status : {}
  const args = Array.isArray(status.args) ? status.args : []
  const architecture = isObject(live.architecture) ? live.architecture : {}
  const modalities = Array.isArray(architecture.input_modalities) ? architecture.input_modalities : []
  const id = live.id as string

  return {
    ...ex,
    name: ex.name ?? id,
    limit: {
      context: perSlotContext(args) ?? ex.limit?.context ?? DEFAULT_CONTEXT,
      output: ex.limit?.output ?? DEFAULT_OUTPUT,
    },
    // llama.cpp serves tool calls for any chat model with a template, so default it on.
    tool_call: ex.tool_call ?? true,
    attachment: ex.attachment ?? modalities.includes("image"),
    reasoning: ex.reasoning ?? REASONING_HINT.test(id),
  }
}

/** Router order, so a model added to the directory shows up without editing anything. */
function buildModels(live: readonly unknown[], existing: JsonObject): Record<string, ModelEntry> {
  const models: Record<string, ModelEntry> = {}
  for (const entry of live) {
    if (!isObject(entry) || typeof entry.id !== "string" || entry.id.length === 0) continue
    if (entry.id in models) continue
    const prior = existing[entry.id]
    models[entry.id] = buildModel(entry, isObject(prior) ? (prior as ModelEntry) : undefined)
  }
  return models
}

async function discover(baseURL: string, fetcher: typeof globalThis.fetch): Promise<unknown[]> {
  const response = await fetcher(modelsURL(baseURL), { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) })
  if (!response.ok) throw new Error(`llama.cpp /v1/models returned HTTP ${response.status}`)
  const payload: unknown = await response.json()
  if (!isObject(payload) || !Array.isArray(payload.data)) {
    throw new Error("invalid response from llama.cpp /v1/models")
  }
  return payload.data
}

/** Fill in every `llamacpp*` provider's `models` from its live router, in memory.
 *
 * Deliberately NOT a write back to opencode.json: that file is Stow-linked into
 * ~/dotfiles, so persisting the list there turns every model added or removed on the
 * box into a tracked diff, and the checked-in config goes stale the moment it is
 * copied to another machine. Discovery happens at every startup instead, and the repo
 * keeps only the provider definition.
 *
 * Tiers are discovered independently and a failure is per-provider: the heavy router
 * being stopped must not empty the light tier's list. */
async function applyDiscovery(
  config: JsonObject,
  fetcher: typeof globalThis.fetch = globalThis.fetch,
): Promise<Record<string, number>> {
  const providers = isObject(config.provider) ? config.provider : {}
  const counts: Record<string, number> = {}

  await Promise.all(
    Object.entries(providers).map(async ([id, value]) => {
      if (!id.startsWith(PROVIDER_PREFIX) || !isObject(value)) return
      const options = isObject(value.options) ? value.options : {}
      const configured = options.baseURL
      if (typeof configured !== "string" || configured.length === 0) return

      // Rewrite the config too, not just the URL used for discovery: opencode sends the
      // actual completions to options.baseURL, so pointing only the probe at loopback
      // would list the models and then fail every request against them.
      const baseURL = resolveBaseURL(configured)
      if (baseURL !== configured) options.baseURL = baseURL

      try {
        const models = buildModels(await discover(baseURL, fetcher), isObject(value.models) ? value.models : {})
        if (Object.keys(models).length === 0) return
        value.models = models
        counts[id] = Object.keys(models).length
      } catch {
        // Router down or not a llama.cpp endpoint -- keep whatever the config declares.
      }
    }),
  )
  return counts
}

// EXACTLY ONE export, and it must be a function. opencode's plugin loader calls every
// export of the module as if it were a plugin (Object.values(mod), each invoked with
// PluginInput), so an exported helper is called with the wrong arguments, throws, and
// takes the whole plugin down with it -- silently, as one "failed to load plugin" line
// in ~/.local/share/opencode/log/opencode.log. Keep helpers module-private.
const LlamaCppModelSyncPlugin: Plugin = async () => ({
  // A router that is down must not take opencode's startup with it: on any failure the
  // provider keeps whatever the config declares, which is normally nothing, so it
  // simply lists no models rather than blocking the client.
  config: async (input) => {
    await applyDiscovery(input as unknown as JsonObject).catch(() => undefined)
  },
})

export default LlamaCppModelSyncPlugin
