import { Controller } from "@hotwired/stimulus"

// The button stays hidden without JavaScript; the text is still there to select by hand.
export default class extends Controller {
  static targets = [ "text", "button" ]

  connect() {
    this.buttonTarget.hidden = false
  }

  copy() {
    navigator.clipboard.writeText(this.textTarget.textContent.trim()).then(() => {
      this.buttonTarget.textContent = "Copied"
      setTimeout(() => { this.buttonTarget.textContent = "Copy" }, 2000)
    })
  }
}
