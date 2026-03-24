const EmojiStream = {
  mounted() {
    this.handleEvent("new_reaction", ({ emoji }) => {
      const el = document.createElement("span");
      el.textContent = emoji;
      el.className = "floating-emoji";
      el.style.left = Math.floor(Math.random() * 80) + "%";
      this.el.appendChild(el);
      el.addEventListener("animationend", () => el.remove());
    });
  }
};

export default EmojiStream;
