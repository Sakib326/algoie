// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"

// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const Hooks = {}

const activeFlashes = new Map()

const dismissFlash = (flash) => {
  if (!flash || flash.dataset.flashDismissing === "true") return

  flash.dataset.flashDismissing = "true"
  window.clearTimeout(flash._dismissTimer)
  flash.classList.add("translate-x-3", "opacity-0")

  window.setTimeout(() => {
    const signature = flash.dataset.flashSignature
    if (activeFlashes.get(signature) === flash) activeFlashes.delete(signature)
    flash.remove()
  }, 200)
}

const initializeFlash = (flash) => {
  if (flash.dataset.flashInitialized === "true") return

  flash.dataset.flashInitialized = "true"
  const signature = `${flash.dataset.flashKind || "notice"}:${flash.textContent.trim()}`
  const duplicate = activeFlashes.get(signature)

  if (duplicate && duplicate !== flash && duplicate.isConnected) {
    dismissFlash(flash)
    return
  }

  flash.dataset.flashSignature = signature
  activeFlashes.set(signature, flash)

  flash.querySelector("[data-flash-close]")?.addEventListener("click", () => dismissFlash(flash))
  flash._dismissTimer = window.setTimeout(() => {
    const closeButton = flash.querySelector("[data-flash-close]")
    if (closeButton) closeButton.click()
    else dismissFlash(flash)
  }, flash.dataset.flashKind === "error" ? 8000 : 5000)
}

document.querySelectorAll("[data-flash]").forEach(initializeFlash)

new MutationObserver((mutations) => {
  mutations.forEach((mutation) => {
    mutation.addedNodes.forEach((node) => {
      if (!(node instanceof Element)) return
      if (node.matches("[data-flash]")) initializeFlash(node)
      node.querySelectorAll?.("[data-flash]").forEach(initializeFlash)
    })
  })
}).observe(document.documentElement, {childList: true, subtree: true})

Hooks.PrintInvoice = {
  mounted() {
    this.el.querySelector("[data-print-invoice]")?.addEventListener("click", () => window.print())
  },
}

Hooks.AssistantChat = {
  mounted() {
    this.loadingOlder = false
    this.requestingOlder = false
    this.scrollToLatest(false)
    this.observeHistorySentinel()
    this.textarea = document.querySelector("#assistant-form textarea")
    this.form = document.querySelector("#assistant-form")
    this.onKeydown = (event) => {
      if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
        event.preventDefault()
        if (!this.textarea.disabled && this.textarea.value.trim()) this.form?.requestSubmit()
      }
    }
    this.textarea?.addEventListener("keydown", this.onKeydown)
  },
  updated() {
    if (this.loadingOlder) {
      window.requestAnimationFrame(() => {
        this.el.scrollTop += this.el.scrollHeight - this.previousScrollHeight
        this.loadingOlder = false
        this.requestingOlder = false
        this.observeHistorySentinel()
      })
    } else {
      this.scrollToLatest(true)
      this.observeHistorySentinel()
    }
    this.textarea = document.querySelector("#assistant-form textarea")
    this.form = document.querySelector("#assistant-form")
    this.textarea?.removeEventListener("keydown", this.onKeydown)
    this.textarea?.addEventListener("keydown", this.onKeydown)
  },
  destroyed() {
    this.textarea?.removeEventListener("keydown", this.onKeydown)
    this.historyObserver?.disconnect()
  },
  scrollToLatest(smooth) {
    window.requestAnimationFrame(() => {
      this.el.scrollTo({top: this.el.scrollHeight, behavior: smooth ? "smooth" : "auto"})
    })
  },
  observeHistorySentinel() {
    this.historyObserver?.disconnect()
    const sentinel = this.el.querySelector("[data-history-sentinel]")
    if (!sentinel || this.el.dataset.hasMore !== "true") return

    this.historyObserver = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting) || this.requestingOlder) return

      this.requestingOlder = true
      this.loadingOlder = true
      this.previousScrollHeight = this.el.scrollHeight
      this.pushEvent("load_older_messages", {})
    }, {root: this.el, rootMargin: "160px 0px 0px", threshold: 0})

    this.historyObserver.observe(sentinel)
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs
window.liveSocket = liveSocket
