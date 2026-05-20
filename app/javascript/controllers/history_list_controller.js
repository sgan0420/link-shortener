import { Controller } from "@hotwired/stimulus"

// Reads localStorage on connect and renders one card per saved entry.
// Mirrors the styling of the server-rendered _result_card so the page
// feels of-a-piece with the form's result list.
export default class extends Controller {
  static targets = [ "entries", "empty" ]
  static STORAGE_KEY = "link-shortener.history"

  connect() {
    const entries = this.#read()
    if (entries.length === 0) return

    this.emptyTarget.remove()
    this.entriesTarget.innerHTML = entries.map(e => this.#renderEntry(e)).join("")
  }

  #read() {
    try {
      const raw = localStorage.getItem(this.constructor.STORAGE_KEY)
      return raw ? JSON.parse(raw) : []
    } catch {
      return []
    }
  }

  #renderEntry(entry) {
    const shortUrl  = this.#escape(entry.short_url)
    const target    = this.#escape(entry.target)
    const savedAt   = this.#escape(this.#formatDate(entry.saved_at))
    const statsPath = `/${this.#escape(entry.slug)}/stats`

    return `
      <article class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm">
        <div class="flex items-baseline justify-between gap-4">
          <a href="${shortUrl}" target="_blank" rel="noopener noreferrer"
             class="truncate text-lg font-mono text-slate-900 underline decoration-slate-300 hover:decoration-slate-900">
            ${shortUrl}
          </a>
          <a href="${statsPath}"
             class="shrink-0 text-sm text-slate-500 hover:text-slate-900">View stats</a>
        </div>
        <p class="mt-1 truncate text-sm text-slate-500" title="${target}">${target}</p>
        <p class="mt-3 text-xs text-slate-400">Saved ${savedAt}</p>
      </article>
    `
  }

  #formatDate(iso) {
    const d = new Date(iso)
    if (Number.isNaN(d.getTime())) return ""
    // YYYY-MM-DD HH:MM — local time so it reads naturally to the visitor.
    const pad = n => String(n).padStart(2, "0")
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
           `${pad(d.getHours())}:${pad(d.getMinutes())}`
  }

  // Minimal HTML-attribute escape. The values we render came from server-
  // controlled fields (slug, short_url) or user input (target_url) that
  // the model already validates as http/https, but localStorage can be
  // tampered with from the console — so escape defensively.
  #escape(value) {
    return String(value || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }
}
