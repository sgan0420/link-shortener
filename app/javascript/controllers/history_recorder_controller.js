import { Controller } from "@hotwired/stimulus"

// Saves a freshly-shortened link to localStorage so the visitor can find
// it again on /history. Attached to the server-rendered result card.
//
// Values come straight from the card's data attributes — the controller
// doesn't read DOM text, so a Turbo Stream that later swaps the title slot
// doesn't trigger redundant writes.
export default class extends Controller {
  static values = {
    slug:      String,
    target:    String,
    shortUrl:  String,
  }

  static STORAGE_KEY = "link-shortener.history"
  static MAX_ENTRIES = 50

  connect() {
    if (!this.slugValue) return

    const entries = this.#read()
    // Dedupe by slug — re-rendering the same card (e.g. via Turbo back/forward)
    // shouldn't push a duplicate.
    if (entries.some(e => e.slug === this.slugValue)) return

    entries.unshift({
      slug:      this.slugValue,
      target:    this.targetValue,
      short_url: this.shortUrlValue,
      saved_at:  new Date().toISOString(),
    })

    this.#write(entries.slice(0, this.constructor.MAX_ENTRIES))
  }

  #read() {
    try {
      const raw = localStorage.getItem(this.constructor.STORAGE_KEY)
      return raw ? JSON.parse(raw) : []
    } catch {
      return []
    }
  }

  #write(entries) {
    try {
      localStorage.setItem(this.constructor.STORAGE_KEY, JSON.stringify(entries))
    } catch {
      // Storage full or disabled — silently ignore; the feature is
      // best-effort polish, not load-bearing.
    }
  }
}
