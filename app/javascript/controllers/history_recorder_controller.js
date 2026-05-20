import { Controller } from "@hotwired/stimulus"

// Records a freshly-shortened slug in localStorage so the visitor can
// find it again on /my-links. Attached to the server-rendered result
// card via a single `slug` value attribute — the page metadata
// (title, target URL, saved-at timestamp) lives on the server and is
// hydrated by the list controller when /my-links loads.
export default class extends Controller {
  static values = { slug: String }

  static STORAGE_KEY = "link-shortener.slugs"
  static MAX_ENTRIES = 50

  connect() {
    if (!this.slugValue) return

    const slugs = this.#read().filter(s => s !== this.slugValue)
    slugs.unshift(this.slugValue)
    this.#write(slugs.slice(0, this.constructor.MAX_ENTRIES))
  }

  #read() {
    try {
      const raw = localStorage.getItem(this.constructor.STORAGE_KEY)
      const parsed = raw ? JSON.parse(raw) : []
      // Defensive: ignore non-string entries (old format had objects).
      return Array.isArray(parsed) ? parsed.filter(s => typeof s === "string") : []
    } catch {
      return []
    }
  }

  #write(slugs) {
    try {
      localStorage.setItem(this.constructor.STORAGE_KEY, JSON.stringify(slugs))
    } catch {
      // Storage full or disabled — silently ignore.
    }
  }
}
