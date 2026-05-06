import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template"]

  add(event) {
    event.preventDefault()
    this.listTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.trim())
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-check-deposit-items-row]")
    if (!row) return

    const rows = this.listTarget.querySelectorAll("[data-check-deposit-items-row]")
    if (rows.length === 1) {
      this.clearRow(row)
    } else {
      row.remove()
    }
  }

  clearRow(row) {
    row.querySelectorAll("input").forEach((input) => {
      input.value = ""
    })
    row.querySelectorAll("select").forEach((select) => {
      select.selectedIndex = 0
    })
  }
}
