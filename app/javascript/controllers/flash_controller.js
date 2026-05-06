import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    autohide: { type: Boolean, default: false },
    delay: { type: Number, default: 4000 }
  }

  connect() {
    if (this.autohideValue) {
      this.timeout = window.setTimeout(() => this.dismiss(), this.delayValue)
    }
  }

  disconnect() {
    this.clearTimer()
  }

  dismiss() {
    this.clearTimer()
    this.element.remove()
  }

  clearTimer() {
    if (this.timeout) {
      window.clearTimeout(this.timeout)
      this.timeout = null
    }
  }
}
