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

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs
window.liveSocket = liveSocket
