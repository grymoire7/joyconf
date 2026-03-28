const googleSlides = require("./google_slides");

const ADAPTERS = [
  {
    match: /docs\.google\.com\/presentation/,
    getSlide: googleSlides.getSlide,
  },
];

/**
 * Returns the adapter for the given URL, or a no-op adapter that always
 * returns slide 0 for unknown/unsupported presentation tools.
 */
function getAdapter(url) {
  const adapter = ADAPTERS.find((a) => a.match.test(url));
  return adapter || { getSlide: () => 0 };
}

module.exports = { getAdapter };
