/**
 * Google Slides adapter.
 *
 * Reads the current slide number from the a11y element's aria-label attribute.
 * Returns 0 if the element is absent or the value cannot be parsed — this
 * is the "unknown slide" sentinel used by the server (reactions go to slide 0).
 *
 * BRITTLE: depends on Google Slides DOM structure. When this test starts
 * failing, update the selector here and the fixture in
 * tests/fixtures/google_slides_dom.html to match the new structure.
 */
function getSlide() {
  const el = document.querySelector('.punch-viewer-svgpage-a11yelement[aria-label*="Slide"]');
  if (!el) return 0;

  const match = el.getAttribute("aria-label").match(/^Slide (\d+)/);
  return match ? parseInt(match[1], 10) : 0;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { getSlide };
} else {
  window.JoyconfGoogleSlidesAdapter = { getSlide };
}
