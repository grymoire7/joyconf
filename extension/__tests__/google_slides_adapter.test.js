const fs = require("fs");
const path = require("path");
const { getSlide } = require("../adapters/google_slides");

function loadFixture(name) {
  const fixturePath = path.join(__dirname, "fixtures", name);
  return fs.readFileSync(fixturePath, "utf-8");
}

describe("Google Slides adapter", () => {
  beforeEach(() => {
    document.body.innerHTML = loadFixture("google_slides_dom.html");
  });

  afterEach(() => {
    document.body.innerHTML = "";
  });

  test("returns the current slide number from the toolbar input", () => {
    expect(getSlide()).toBe(3);
  });

  test("returns 0 when the slide indicator element is absent", () => {
    document.body.innerHTML = "<div>no slides here</div>";
    expect(getSlide()).toBe(0);
  });

  test("returns 0 when the value is not a valid number", () => {
    const input = document.querySelector('input[aria-label*="Slide"]');
    input.value = "abc";
    expect(getSlide()).toBe(0);
  });
});
