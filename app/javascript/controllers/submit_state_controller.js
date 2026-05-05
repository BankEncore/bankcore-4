import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    label: { type: String, default: "Submitting..." }
  }

  connect() {
    this.originalStates = new Map()
  }

  start() {
    this.submitElements().forEach((element) => {
      this.originalStates.set(element, this.snapshot(element))
      element.disabled = true
      this.setLabel(element, this.pendingLabelFor(element))
      element.classList.add("opacity-75", "cursor-wait")
    })
  }

  end(event) {
    const succeeded = event.detail?.success
    if (succeeded) return

    this.submitElements().forEach((element) => {
      const original = this.originalStates.get(element)
      element.disabled = false
      element.classList.remove("opacity-75", "cursor-wait")
      if (original) this.restore(element, original)
    })
  }

  submitElements() {
    return Array.from(
      this.element.querySelectorAll("input[type='submit'], button[type='submit']")
    )
  }

  snapshot(element) {
    if (element.tagName === "INPUT") {
      return { type: "input", label: element.value }
    }

    return { type: "button", label: element.textContent }
  }

  restore(element, original) {
    if (original.type === "input") {
      element.value = original.label
    } else {
      element.textContent = original.label
    }
  }

  setLabel(element, label) {
    if (element.tagName === "INPUT") {
      element.value = label
    } else {
      element.textContent = label
    }
  }

  pendingLabelFor(element) {
    return element.dataset.submittingLabel || this.labelValue
  }
}
