/**
 * Google Slides adapter.
 *
 * Reads the current slide number from the slide-indicator toolbar input.
 * Returns 0 if the element is absent or the value cannot be parsed — this
 * is the "unknown slide" sentinel used by the server (reactions go to slide 0).
 *
 * BRITTLE: depends on Google Slides DOM structure. When this test starts
 * failing, update the selector here and the fixture in
 * __tests__/fixtures/google_slides_dom.html to match the new structure.
 */
function getSlide() {
  const input = document.querySelector('input[aria-label*="Slide"]');
  if (!input) return 0;

  const n = parseInt(input.value, 10);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { getSlide };
} else {
  window.JoyconfGoogleSlidesAdapter = { getSlide };
}
