const { getAdapter } = require("../adapters/index");

describe("adapter registry", () => {
  test("returns Google Slides adapter for Google Slides URLs", () => {
    const adapter = getAdapter(
      "https://docs.google.com/presentation/d/abc123/edit"
    );
    expect(typeof adapter.getSlide).toBe("function");
  });

  test("returns fallback adapter for unknown URLs", () => {
    const adapter = getAdapter("https://example.com/my-slides");
    expect(adapter.getSlide()).toBe(0);
  });

  test("fallback adapter always returns 0", () => {
    const adapter = getAdapter("https://slides.com/user/deck");
    expect(adapter.getSlide()).toBe(0);
  });
});
