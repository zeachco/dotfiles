import { chmod, readFile, realpath, rename, stat, unlink, writeFile } from "node:fs/promises"
import { randomUUID } from "node:crypto"
import { fileURLToPath } from "node:url"
import type { Plugin } from "@opencode-ai/plugin"

const PROVIDER_ID = "llamacpp"
const FETCH_TIMEOUT_MS = 5_000
const CONFIG_PATH = fileURLToPath(new URL("../opencode.json", import.meta.url))

type JsonObject = Record<string, unknown>

export type SyncResult = {
  config: JsonObject
  added: number
  removed: number
}

export type SyncDependencies = {
  fetch?: typeof globalThis.fetch
  notify?: (message: string) => Promise<void>
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function parseConfig(contents: string): JsonObject {
  const parsed: unknown = JSON.parse(contents)
  if (!isObject(parsed)) throw new Error("OpenCode config must be a JSON object")
  return parsed
}

function providerFrom(config: JsonObject): JsonObject | undefined {
  if (!isObject(config.provider)) return undefined
  const provider = config.provider[PROVIDER_ID]
  return isObject(provider) ? provider : undefined
}

function endpointFrom(config: JsonObject): URL | undefined {
  const provider = providerFrom(config)
  if (!provider || !isObject(provider.options)) return undefined
  const baseURL = provider.options.baseURL
  if (typeof baseURL !== "string" || baseURL.length === 0) return undefined

  try {
    return new URL("models", baseURL.endsWith("/") ? baseURL : `${baseURL}/`)
  } catch {
    return undefined
  }
}

function modelIDs(response: unknown): string[] {
  if (!isObject(response) || !Array.isArray(response.data)) {
    throw new Error("Invalid response from llama.cpp /v1/models")
  }

  const seen = new Set<string>()
  const ids: string[] = []
  for (const item of response.data) {
    if (!isObject(item) || typeof item.id !== "string" || item.id.length === 0) continue
    if (seen.has(item.id)) continue
    seen.add(item.id)
    ids.push(item.id)
  }
  return ids
}

export function synchronizeModels(config: JsonObject, remoteIDs: readonly string[]): SyncResult {
  const provider = providerFrom(config)
  if (!provider) return { config, added: 0, removed: 0 }

  const currentModels = isObject(provider.models) ? provider.models : {}
  const orderedRemoteIDs = [...new Set(remoteIDs)]
  const remote = new Set(orderedRemoteIDs)
  const entries: Array<[string, unknown]> = []
  let removed = 0

  for (const [id, model] of Object.entries(currentModels)) {
    if (remote.has(id)) entries.push([id, model])
    else removed++
  }

  let added = 0
  for (const id of orderedRemoteIDs) {
    if (Object.hasOwn(currentModels, id)) continue
    entries.push([id, { name: id }])
    added++
  }

  if (added === 0 && removed === 0) return { config, added, removed }

  const nextProvider = { ...provider, models: Object.fromEntries(entries) }
  const nextProviders = { ...(config.provider as JsonObject), [PROVIDER_ID]: nextProvider }
  return { config: { ...config, provider: nextProviders }, added, removed }
}

function modelCount(count: number, action: "added" | "removed"): string {
  return `${count} ${count === 1 ? "model" : "models"} ${action}`
}

export function notificationMessage(added: number, removed: number): string {
  const changes: string[] = []
  if (added > 0) changes.push(modelCount(added, "added"))
  if (removed > 0) changes.push(modelCount(removed, "removed"))
  return `${changes.join(", ")}, changes effect next restart`
}

async function atomicWrite(path: string, contents: string): Promise<void> {
  const mode = (await stat(path)).mode
  const temporary = `${path}.${process.pid}.${randomUUID()}.tmp`
  try {
    await writeFile(temporary, contents, { encoding: "utf8", flag: "wx", mode })
    await chmod(temporary, mode)
    await rename(temporary, path)
  } catch (error) {
    await unlink(temporary).catch(() => undefined)
    throw error
  }
}

export async function syncConfigFile(
  configPath: string,
  dependencies: SyncDependencies = {},
): Promise<SyncResult | undefined> {
  const fetcher = dependencies.fetch ?? globalThis.fetch
  const resolvedPath = await realpath(configPath)
  const initialConfig = parseConfig(await readFile(resolvedPath, "utf8"))
  const endpoint = endpointFrom(initialConfig)
  if (!endpoint) return undefined

  const response = await fetcher(endpoint, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) })
  if (!response.ok) throw new Error(`llama.cpp /v1/models returned HTTP ${response.status}`)
  const remoteIDs = modelIDs(await response.json())

  const latestConfig = parseConfig(await readFile(resolvedPath, "utf8"))
  if (endpointFrom(latestConfig)?.href !== endpoint.href) return undefined
  const result = synchronizeModels(latestConfig, remoteIDs)
  if (result.added === 0 && result.removed === 0) return result

  await atomicWrite(resolvedPath, `${JSON.stringify(result.config, null, 2)}\n`)
  await dependencies.notify?.(notificationMessage(result.added, result.removed))
  return result
}

const LlamaCppModelSyncPlugin: Plugin = async ({ client, directory }) => {
  void syncConfigFile(CONFIG_PATH, {
    notify: async (message) => {
      await client.tui.showToast({
        body: {
          title: "llama.cpp models updated",
          message,
          variant: "success",
        },
        query: { directory },
      })
    },
  }).catch(() => undefined)

  return {}
}

export default LlamaCppModelSyncPlugin
