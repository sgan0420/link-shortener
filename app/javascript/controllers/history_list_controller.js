import { Controller } from "@hotwired/stimulus"

// Reads the slug list from localStorage on connect, POSTs it to the
// server (which returns rendered card partials), and injects the
// response HTML into the entries target. Server is the source of
// truth for title, target URL, and saved-at timestamp; localStorage
// only knows "which slugs has this browser shortened".
export default class extends Controller {
  static targets = [ "entries", "empty" ]
  static values  = { endpoint: String }

  static STORAGE_KEY = "link-shortener.slugs"

  async connect() {
    const slugs = this.#read()
    if (slugs.length === 0) return  // empty state stays visible

    let html
    try {
      const response = await fetch(this.endpointValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept":       "text/html",
          "X-CSRF-Token": this.#csrfToken(),
        },
        body: JSON.stringify({ slugs }),
      })
      if (!response.ok) throw new Error(`Lookup failed: ${response.status}`)
      html = (await response.text()).trim()
    } catch (err) {
      console.warn("[my-links] lookup failed:", err)
      return  // empty state stays visible
    }

    if (!html) return  // server returned no matching links

    this.emptyTarget.remove()
    this.entriesTarget.innerHTML = html
  }

  #read() {
    try {
      const raw = localStorage.getItem(this.constructor.STORAGE_KEY)
      const parsed = raw ? JSON.parse(raw) : []
      return Array.isArray(parsed) ? parsed.filter(s => typeof s === "string") : []
    } catch {
      return []
    }
  }

  #csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
