import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

for (const width of [320, 390, 768, 1440]) {
  test(`page fits ${width}px and loads the real captures`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({ reducedMotion: "reduce" });
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("response", (response) => {
      if (response.status() >= 400)
        errors.push(`${response.status()}: ${response.url()}`);
    });
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(
      "A way forward.Even off-grid.",
    );
    for (const selector of [
      ".hero",
      "#the-idea",
      "#why-gatisaarth",
      "#your-journey",
      "#intelligence",
      "#download",
      ".faq-section",
    ]) {
      await page.locator(selector).scrollIntoViewIfNeeded();
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth,
        ),
      ).toBe(true);
    }
    for (const capture of await page.locator(".device img").all()) {
      await capture.scrollIntoViewIfNeeded();
      await expect(capture).toBeVisible();
      expect(
        await capture.evaluate(
          (img) => img.complete && img.naturalWidth === 1280,
        ),
      ).toBe(true);
    }
    await expect(page.getByRole("button", { name: "View demo" })).toBeEnabled();
    expect(errors).toEqual([]);
    await page.evaluate(() => scrollTo(0, 0));
    await page.screenshot({ path: `test-results/hero-${width}.png` });
    await page.screenshot({
      path: `test-results/launch-${width}.png`,
      fullPage: true,
    });
  });
}

test("signal explorer changes the explanation and active state", async ({
  page,
}) => {
  await page.goto("/");
  for (const [stage, title] of [
    ["sky", "Start with a reliable point of reference."],
    ["return", "Back under the sky. Back in alignment."],
    ["tunnel", "The signal fades. Motion still tells a story."],
  ]) {
    const button = page.locator(`button[data-signal="${stage}"]`);
    await button.click();
    await expect(button).toHaveAttribute("aria-pressed", "true");
    await expect(page.locator("#signal-title")).toHaveText(title);
    await expect(
      page.locator('.signal-controls [aria-pressed="true"]'),
    ).toHaveCount(1);
  }
});

test("mobile menu supports links and Escape", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await page.getByRole("button", { name: "Open menu" }).click();
  await expect(
    page.getByRole("navigation", { name: "Mobile navigation" }),
  ).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("button", { name: "Open menu" })).toBeFocused();
  await page.getByRole("button", { name: "Open menu" }).click();
  await page
    .locator("#mobile-menu")
    .getByRole("link", { name: "Your journey" })
    .click();
  await expect(page.locator("#mobile-menu")).toBeHidden();
  await expect(page).toHaveURL(/#your-journey$/);
});

test("both actual screenshots enlarge and restore keyboard focus", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  for (const name of ["navigation", "home"]) {
    const trigger = page.getByRole("button", {
      name: `Enlarge the actual GatiSaarth ${name} screen`,
    });
    await trigger.click();
    await expect(page.getByRole("dialog")).toBeVisible();
    await expect(page.locator("#enlarged-screenshot")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.getByRole("dialog")).toBeHidden();
    await expect(trigger).toBeFocused();
    expect(await page.evaluate(() => document.body.style.overflow)).toBe("");
  }
});

test("download is the APK described on the page and checksum copies", async ({
  page,
  context,
}) => {
  test.slow();
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await page.goto("/");
  const downloadPromise = page.waitForEvent("download");
  await page
    .locator(".hero")
    .getByRole("link", { name: "Download APK" })
    .click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe("gatisaarth-5.2.1.apk");
  const apk = await readFile(await download.path());
  expect(apk.length).toBe(113704871);
  expect(apk.subarray(0, 2).toString()).toBe("PK");
  const hash = createHash("sha256").update(apk).digest("hex");
  await page.locator(".installation-details summary").click();
  await expect(page.locator("#apk-hash")).toHaveText(hash);
  await page.getByRole("button", { name: "Copy checksum" }).click();
  await expect(page.getByRole("status")).toHaveText("Checksum copied");
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(hash);
});

test("engineering and FAQ details disclose content", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("link", { name: "Explore the engineering" }).click();
  await expect(page.locator(".technical-grid")).toBeVisible();
  await page.locator(".faq-list summary").first().click();
  await expect(page.locator(".faq-list details").first()).toHaveAttribute(
    "open",
    "",
  );
});

test("reduced motion disables movement and desktop has no serious accessibility issues", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  expect(
    await page
      .locator(".hero-route")
      .evaluate((el) => getComputedStyle(el).animationName),
  ).toBe("none");
  expect(
    await page.evaluate(
      () => getComputedStyle(document.documentElement).scrollBehavior,
    ),
  ).toBe("auto");
  const result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
    .analyze();
  expect(result.violations).toEqual([]);
});

test("mobile disclosures remain accessible when expanded", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await page.evaluate(() => document.fonts.ready);
  for (const detail of await page.locator("details").all()) {
    if ((await detail.getAttribute("open")) === null) {
      await detail.locator("summary").click();
    }
  }
  const result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
    .analyze();
  expect(result.violations).toEqual([]);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});

test("scrollbars are hidden while wheel and keyboard scrolling still work", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  expect(
    await page.evaluate(
      () => getComputedStyle(document.documentElement).scrollbarWidth,
    ),
  ).toBe("none");
  await page.mouse.wheel(0, 500);
  await expect.poll(() => page.evaluate(() => scrollY)).toBeGreaterThan(100);
  const before = await page.evaluate(() => scrollY);
  await page.locator("body").click({ position: { x: 10, y: 10 } });
  await page.keyboard.press("PageDown");
  await expect.poll(() => page.evaluate(() => scrollY)).toBeGreaterThan(before);
});

test("visual comparison explains signal loss and keeps its controls usable", async ({
  page,
}) => {
  await page.goto("/");
  await page
    .getByRole("button", { name: "Signal available", exact: true })
    .click();
  await expect(page.locator(".capability-board")).toHaveAttribute(
    "data-reception",
    "available",
  );
  await expect(page.locator("#motion-result")).toHaveText(
    "Satellite fixes anchor the motion estimate.",
  );
  await page.getByRole("button", { name: "Signal lost", exact: true }).click();
  await expect(page.locator(".capability-board")).toHaveAttribute(
    "data-reception",
    "lost",
  );
  await expect(page.locator("#motion-result")).toHaveText(
    "Motion carries the estimate forward.",
  );
  await expect(
    page.locator('.reception-controls [aria-pressed="true"]'),
  ).toHaveCount(1);
  await expect(page.locator(".screenshot-caption")).toContainText(
    "Mumbai, Maharashtra",
  );
  await expect(page.locator(".team-credit")).toContainText("Team CodeAstra");
  await expect(page.locator(".team-credit")).toContainText("120431");
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page
    .locator("#why-gatisaarth")
    .screenshot({ path: "test-results/product-difference.png" });
});

test("GSAP reveals scroll scenes and reverts when reduced motion is requested", async ({
  page,
}) => {
  await page.goto("/");
  const scene = page.locator(".difference-heading");
  await scene.scrollIntoViewIfNeeded();
  await expect(scene).toHaveCSS("opacity", "1");
  await expect(page.locator(".capability-track").first()).toHaveCSS(
    "opacity",
    "1",
  );
  await page.emulateMedia({ reducedMotion: "reduce" });
  await expect(page.locator(".fusion-output")).toHaveCSS("opacity", "1");
  expect(
    await page
      .locator(".hero-art")
      .evaluate((el) => el.style.getPropertyValue("--scroll-shift")),
  ).toBe("");
  await page
    .getByRole("button", { name: "Signal available", exact: true })
    .click();
  await expect(page.locator(".capability-board")).toHaveAttribute(
    "data-reception",
    "available",
  );
});

for (const width of [390, 1440]) {
  test(`launch film plays on demand and closes cleanly at ${width}px`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({ reducedMotion: "reduce" });
    // Exercise the usable inline fallback when fullscreen is denied.
    await page.addInitScript(() => {
      HTMLVideoElement.prototype.requestFullscreen = () =>
        Promise.reject(new DOMException("Denied", "NotAllowedError"));
    });
    const mediaRequests = [];
    page.on("request", (request) => {
      if (request.url().includes(".mp4")) mediaRequests.push(request.url());
    });
    await page.goto("/");
    const video = page.locator("#demo-video");
    expect(await video.getAttribute("src")).toBeNull();
    expect(mediaRequests).toEqual([]);
    const trigger = page.getByRole("button", { name: "View demo" });
    await trigger.click();
    await expect(page.locator("#demo-dialog")).toBeVisible();
    await expect
      .poll(() => video.evaluate((v) => v.readyState), { timeout: 20000 })
      .toBeGreaterThanOrEqual(2);
    expect(
      await video.evaluate((v) => [v.videoWidth, v.videoHeight, v.duration]),
    ).toEqual([1920, 1080, 60]);
    await expect
      .poll(() => video.evaluate((v) => v.currentTime))
      .toBeGreaterThan(0);
    expect(await video.evaluate((v) => v.paused)).toBe(false);
    expect(mediaRequests.length).toBeGreaterThan(0);
    expect(await page.evaluate(() => document.body.style.overflow)).toBe(
      "hidden",
    );
    const bounds = await page.locator("#demo-dialog").boundingBox();
    expect(bounds.x).toBeGreaterThanOrEqual(0);
    expect(bounds.x + bounds.width).toBeLessThanOrEqual(width);
    await page.screenshot({ path: `test-results/demo-${width}.png` });
    await page.keyboard.press("Escape");
    await expect(page.locator("#demo-dialog")).not.toBeVisible();
    expect(await video.evaluate((v) => v.paused)).toBe(true);
    expect(await page.evaluate(() => document.body.style.overflow)).toBe("");
    await expect(trigger).toBeFocused();
    await page
      .getByText("Where can I watch the demo?", { exact: true })
      .click();
    const faqTrigger = page.getByRole("button", {
      name: "Watch the 60-second launch film",
    });
    await faqTrigger.click();
    await expect(page.locator("#demo-dialog")).toBeVisible();
    await page.getByRole("button", { name: "Close video" }).click();
    await expect(faqTrigger).toBeFocused();
    expect(await video.evaluate((v) => v.paused)).toBe(true);
  });
}

test("mobile fullscreen requests landscape and releases it on exit", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(() => {
    window.filmCalls = [];
    let fullscreen = null;
    Object.defineProperty(document, "fullscreenEnabled", { get: () => true });
    Object.defineProperty(document, "fullscreenElement", {
      get: () => fullscreen,
    });
    HTMLVideoElement.prototype.requestFullscreen = async function () {
      window.filmCalls.push("fullscreen");
      fullscreen = this;
    };
    document.exitFullscreen = async () => {
      fullscreen = null;
      document.dispatchEvent(new Event("fullscreenchange"));
    };
    screen.orientation.lock = async (orientation) =>
      window.filmCalls.push(orientation);
    screen.orientation.unlock = () => window.filmCalls.push("unlock");
  });
  await page.goto("/");
  await page.getByRole("button", { name: "View demo", exact: true }).click();
  await expect
    .poll(() => page.evaluate(() => window.filmCalls))
    .toEqual(["fullscreen", "landscape"]);
  await expect(page.locator("#rotate-hint")).toBeHidden();
  await page.evaluate(() => document.exitFullscreen());
  await expect
    .poll(() => page.evaluate(() => window.filmCalls))
    .toEqual(["fullscreen", "landscape", "unlock"]);
  await page.getByRole("button", { name: "Close video" }).click();
  await expect(page.locator("#demo-dialog")).toBeHidden();
});

test("mobile WebKit native player fallback and blocked rotation stay usable", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(() => {
    Object.defineProperty(document, "fullscreenEnabled", { get: () => false });
    HTMLVideoElement.prototype.webkitEnterFullscreen = function () {
      this.dataset.nativeFullscreenRequested = "true";
    };
  });
  await page.goto("/");
  await page.getByRole("button", { name: "View demo", exact: true }).click();
  await expect(page.locator("#demo-video")).toHaveAttribute(
    "data-native-fullscreen-requested",
    "true",
  );
  await expect(page.locator("#rotate-hint")).toBeVisible();
  await page.getByRole("button", { name: "Close video" }).click();
  await expect(page.locator("#demo-dialog")).toBeHidden();
});

test("journey reading progress reverts for reduced motion", async ({
  page,
}) => {
  await page.goto("/");
  const step = page.locator(".journey-steps li").first();
  await step.scrollIntoViewIfNeeded();
  await expect
    .poll(() =>
      step.evaluate((el) =>
        Number(el.style.getPropertyValue("--step-progress")),
      ),
    )
    .toBeGreaterThan(0);
  await page.emulateMedia({ reducedMotion: "reduce" });
  expect(
    await step.evaluate((el) => el.style.getPropertyValue("--step-progress")),
  ).toBe("");
  await expect(step).toHaveCSS("opacity", "1");
});

for (const width of [390, 1440]) {
  test(`scroll scenes advance and reverse after manual input at ${width}px`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto("/");
    for (const scene of [
      {
        selector: ".signal-stage",
        attr: "data-signal",
        start: 0.78,
        end: 0.45,
        states: [
          [0.1, "sky"],
          [0.5, "tunnel"],
          [0.95, "return"],
          [0.5, "tunnel"],
          [0.1, "sky"],
        ],
        manual: 'button[data-signal="return"]',
      },
      {
        selector: ".capability-board",
        attr: "data-reception",
        start: 0.85,
        end: 0.55,
        states: [
          [0.1, "available"],
          [0.7, "lost"],
          [0.1, "available"],
        ],
        manual: 'button[data-reception="lost"]',
      },
    ]) {
      const element = page.locator(scene.selector);
      await element.scrollIntoViewIfNeeded();
      await expect(element).toHaveCSS("opacity", "1");
      const limits = await element.evaluate((el, scene) => {
        const rect = el.getBoundingClientRect();
        return {
          start: rect.top + scrollY - innerHeight * scene.start,
          end: rect.bottom + scrollY - innerHeight * scene.end,
        };
      }, scene);
      const scrollProgress = async (progress) =>
        page.evaluate(
          (y) => scrollTo({ top: y, behavior: "instant" }),
          limits.start + (limits.end - limits.start) * progress,
        );
      for (const [progress, state] of scene.states) {
        await scrollProgress(progress);
        await expect(element).toHaveAttribute(scene.attr, state);
      }
      // DOM click avoids test-runner scrolling the control to a different segment.
      await page.locator(scene.manual).evaluate((button) => button.click());
      await expect(element).toHaveAttribute(
        scene.attr,
        scene.states[scene.states.length === 5 ? 2 : 1][1],
      );
      await scrollProgress(0.15);
      await expect(element).toHaveAttribute(
        scene.attr,
        scene.states[scene.states.length === 5 ? 2 : 1][1],
      );
      await scrollProgress(0.7);
      await expect(element).toHaveAttribute(scene.attr, scene.states[1][1]);
      await scrollProgress(0.1);
      await expect(element).toHaveAttribute(scene.attr, scene.states[0][1]);
    }
  });
}

test("official logo and name branding are rendered and loaded cleanly", async ({
  page,
}) => {
  await page.goto("/");
  const logos = [".site-header .brand-logo", ".site-footer .brand-logo"];
  for (const selector of logos) {
    const img = page.locator(selector);
    await expect(img).toBeAttached();
    const isLoaded = await img.evaluate(
      (el) => el.complete && el.naturalWidth > 0,
    );
    expect(isLoaded).toBe(true);
  }
  await expect(page.locator(".download-brand")).toContainText("GatiSaarth.");
  await expect(page.locator(".fusion-core")).toContainText("GatiSaarth");
  await expect(page.locator(".fusion-core")).toContainText(
    "On-device fusion engine",
  );
  const favicon = page.locator('link[rel="icon"]');
  await expect(favicon).toHaveAttribute("href", "./assets/brand/logo.png");
});
