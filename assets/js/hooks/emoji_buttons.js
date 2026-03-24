const EmojiButtons = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      if (e.target.tagName !== "BUTTON") return;

      const buttons = this.el.querySelectorAll("button");
      buttons.forEach(b => b.setAttribute("disabled", "true"));
      this.el.classList.add("cooling-down");

      const label = this.el.querySelector(".cooldown-label");
      let remaining = 5;
      if (label) label.textContent = `Cooling down… ${remaining}s`;

      const tick = setInterval(() => {
        remaining -= 1;
        if (label) {
          label.textContent = remaining > 0 ? `Cooling down… ${remaining}s` : "Tap to react";
        }
        if (remaining <= 0) {
          clearInterval(tick);
          buttons.forEach(b => b.removeAttribute("disabled"));
          this.el.classList.remove("cooling-down");
        }
      }, 1000);
    });
  }
};

export default EmojiButtons;
