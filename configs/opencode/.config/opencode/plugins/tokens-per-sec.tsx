/** @jsxImportSource @opentui/solid */
import { createSignal, Show } from "solid-js"
import type { AssistantMessage } from "@opencode-ai/sdk/v2"
import type { TuiPlugin, TuiPluginApi, TuiPluginModule } from "@opencode-ai/plugin/tui"

const id = "tokens-per-sec"
const TICK_MS = 1000
const MIN_SECONDS = 0.2

function isAssistant(message: unknown): message is AssistantMessage {
  if (typeof message !== "object" || message === null) return false
  return (message as AssistantMessage).role === "assistant"
}

function messageTokens(message: AssistantMessage): number {
  return message.tokens.output + message.tokens.reasoning
}

function computeRate(api: TuiPluginApi): number | undefined {
  const route = api.route.current
  const sessionID = "params" in route ? route.params?.sessionID : undefined
  if (route.name !== "session" || typeof sessionID !== "string") return undefined
  const messages = api.state.session.messages(sessionID)
  let last: AssistantMessage | undefined
  for (let index = messages.length - 1; index >= 0; index--) {
    const message = messages[index]
    if (isAssistant(message) && message.tokens.output > 0) {
      last = message
      break
    }
  }
  if (!last) return undefined
  const tokens = messageTokens(last)
  if (tokens <= 0) return undefined
  const ended = last.time.completed ?? Date.now()
  const seconds = (ended - last.time.created) / 1000
  if (seconds < MIN_SECONDS) return undefined
  return tokens / seconds
}

function formatRate(rate: number): string {
  if (rate >= 1000) return `${(rate / 1000).toFixed(1)}k tok/s`
  if (rate >= 100) return `${Math.round(rate)} tok/s`
  return `${rate.toFixed(1)} tok/s`
}

const tui: TuiPlugin = async (api) => {
  const [rate, setRate] = createSignal<number | undefined>(undefined)

  const tick = () => {
    try {
      setRate(computeRate(api))
    } catch {
      setRate(undefined)
    }
  }
  tick()
  const timer = setInterval(tick, TICK_MS)
  api.lifecycle.onDispose(() => clearInterval(timer))

  api.slots.register({
    order: 100,
    slots: {
      session_prompt_right() {
        return (
          <Show when={rate()}>
            {(value) => <text fg={api.theme.current.textMuted}>{formatRate(value())}</text>}
          </Show>
        )
      },
    },
  })
}

const plugin: TuiPluginModule & { id: string } = {
  id,
  tui,
}

export default plugin
