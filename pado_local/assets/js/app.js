import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/pado_local"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
window.addEventListener("phx:clear-chat-composer", event => {
  const form = document.getElementById(event.detail.id)
  const textarea = form?.querySelector("textarea[name='message']")

  if (textarea) {
    textarea.value = ""
    textarea.dispatchEvent(new Event("input", {bubbles: true}))
  }
})

const hooks = {
  ChatComposer: {
    mounted() {
      this.onKeyDown = event => {
        const isMessageTextarea =
          event.target instanceof HTMLTextAreaElement && event.target.name === "message"

        if (
          !isMessageTextarea ||
          event.key !== "Enter" ||
          event.shiftKey ||
          event.altKey ||
          event.ctrlKey ||
          event.metaKey ||
          event.repeat ||
          event.isComposing ||
          event.keyCode === 229
        ) {
          return
        }

        event.preventDefault()
        this.el.requestSubmit()
      }

      this.el.addEventListener("keydown", this.onKeyDown)
    },
    destroyed() {
      this.el.removeEventListener("keydown", this.onKeyDown)
    },
  },
  SessionScroll: {
    mounted() {
      this.scrollToBottom()
    },
    updated() {
      this.scrollToBottom()
    },
    scrollToBottom() {
      requestAnimationFrame(() => {
        this.el.scrollTop = this.el.scrollHeight
      })
    },
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...hooks},
})

// LiveView 이동과 폼 제출 중 진행 상태를 표시한다.
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()

// 브라우저 콘솔에서 LiveSocket 디버깅과 지연 시뮬레이션을 사용할 수 있게 한다.
window.liveSocket = liveSocket

// 개발 환경에서 Phoenix LiveReload 편의 기능을 활성화한다.
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
