import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

async function openApp(page, width = 1440, height = 1000) {
  await page.setViewportSize({ width, height });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  const app = page.locator("gati-simulator");
  await expect(app.locator(".city-svg")).toBeVisible({ timeout: 20000 });
  await page
    .getByRole("button", { name: "Experience app", exact: true })
    .click();
  await expect(page.locator("#app-experience")).toBeVisible();
  return app;
}

test("judge can plan a route, navigate, record, and recover from a signal gap", async ({
  page,
}) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const app = await openApp(page);
  await app.getByRole("button", { name: "Home", exact: true }).click();
  await app.getByRole("button", { name: "End", exact: true }).click();
  await app.getByRole("button", { name: "End journey", exact: true }).click();
  await app.locator('[data-action="plan"]').click();
  await app
    .getByRole("textbox", { name: "Destination", exact: true })
    .fill("Marine");
  await app.getByRole("button", { name: /Marine Drive Queen/ }).click();
  await expect(
    app.getByRole("button", { name: "Start navigation", exact: true }),
  ).toBeVisible();
  await app
    .getByRole("button", { name: "Start navigation", exact: true })
    .click();
  await expect(app.locator("[data-speed]")).not.toHaveText("0");
  const before = await app.locator(".position-dot").getAttribute("cy");
  await expect
    .poll(() => app.locator(".position-dot").getAttribute("cy"))
    .not.toBe(before);
  await app.getByRole("button", { name: "Record drive", exact: true }).click();
  await app
    .getByRole("button", { name: "Simulation Lab", exact: true })
    .click();
  await app.getByRole("button", { name: "Tunnel test", exact: true }).click();
  await expect(app.locator("[data-signal]")).toHaveText("Dead reckoning");
  await expect
    .poll(() => app.locator("[data-accuracy]").first().textContent())
    .not.toBe("±5 m");
  await app
    .getByRole("button", {
      name: "End test",
      exact: true,
    })
    .click();
  await expect(app.locator("[data-signal]")).toHaveText("GNSS locked");
  await app.getByRole("button", { name: /Stop recording/ }).click();
  await app.getByRole("button", { name: "Profile", exact: true }).click();
  await app
    .getByRole("button", { name: /Drive recordings 1 saved locally/ })
    .click();
  await expect(app.locator(".record-item")).toContainText("Marine Drive");
  const download = page.waitForEvent("download");
  await app.getByRole("button", { name: "Export recording" }).click();
  expect((await download).suggestedFilename()).toBe(
    "gatisaarth-simulated-drive.json",
  );
  expect(errors).toEqual([]);
});

for (const [width, height] of [
  [320, 740],
  [390, 844],
  [768, 1024],
  [1024, 768],
  [1440, 1000],
  [844, 390],
]) {
  test(`app adapts at ${width}x${height} and retains state on expand/close`, async ({
    page,
  }) => {
    const app = await openApp(page, width, height);
    const rect = await app.boundingBox();
    expect(rect.x).toBeGreaterThanOrEqual(0);
    expect(rect.x + rect.width).toBeLessThanOrEqual(width + 1);
    expect(rect.y + rect.height).toBeLessThanOrEqual(height + 1);
    const record = await app
      .getByRole("button", { name: "Record drive", exact: true })
      .boundingBox();
    expect(record.y + record.height).toBeLessThanOrEqual(height);
    await app.getByRole("button", { name: "Home", exact: true }).click();
    await expect(
      app.getByRole("heading", { name: "Home", exact: true }),
    ).toBeVisible();
    await page.screenshot({ path: `test-results/app-home-${width}.png` });
    await page.getByRole("button", { name: "Close app experience" }).click();
    await expect(page.locator("#hero-app-mount gati-simulator")).toBeVisible();
    await expect(
      app.getByRole("heading", { name: "Home", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Experience app", exact: true }),
    ).toBeFocused();
    expect(await page.evaluate(() => document.body.style.overflow)).toBe("");
  });
}

test("map zoom, typed inputs, vehicle preferences, and system health are interactive", async ({
  page,
}) => {
  const app = await openApp(page);
  const box = await app.locator(".city-svg").getAttribute("viewBox");
  await app.getByRole("button", { name: "Zoom in", exact: true }).click();
  expect(await app.locator(".city-svg").getAttribute("viewBox")).not.toBe(box);
  await app.getByRole("button", { name: "Recenter map", exact: true }).click();
  await expect(app.locator(".city-svg")).toHaveAttribute("viewBox", box);
  await page.screenshot({ path: "test-results/app-map-desktop.png" });
  await app.getByRole("button", { name: "Sensors", exact: true }).click();
  await app.locator("summary").click();
  await expect(app.locator(".diagnostic-grid")).toBeVisible();
  await app.getByRole("button", { name: "Profile", exact: true }).click();
  await app.getByRole("button", { name: "Walk", exact: true }).click();
  await expect(
    app.getByRole("button", { name: "Walk", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await app.getByRole("switch", { name: /Appearance/ }).click();
  await expect(app.locator(".shell")).toHaveClass(/light/);
  await page.getByRole("button", { name: "Close app experience" }).click();
  await page.reload();
  await expect(app.locator(".shell")).toHaveClass(/light/);
});

test("app loads without third-party map requests and supports keyboard dismissal", async ({
  page,
}) => {
  const outside = [];
  page.on("request", (request) => {
    if (
      !request.url().startsWith("http://127.0.0.1:4173") &&
      !request.url().startsWith("data:")
    )
      outside.push(request.url());
  });
  const app = await openApp(page, 390, 844);
  await app
    .getByRole("button", { name: "Simulation Lab", exact: true })
    .click();
  await page.keyboard.press("Escape");
  await expect(app.locator(".sheet")).toHaveCount(0);
  await expect(page.locator("#app-experience")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator("#app-experience")).toBeHidden();
  expect(outside).toEqual([]);
});

test("destination changes can be cancelled and map-picked routes can be started", async ({
  page,
}) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const app = await openApp(page);
  await app.getByRole("button", { name: "Home", exact: true }).click();
  await app.getByRole("button", { name: "Plan another journey" }).click();
  await app
    .getByRole("textbox", { name: "Destination", exact: true })
    .fill("No such place");
  await expect(app.locator(".empty")).toBeVisible();
  await app.getByRole("button", { name: "Back", exact: true }).click();
  await expect(
    app.getByRole("heading", { name: "Gateway of India", exact: true }),
  ).toBeVisible();
  await app.getByRole("button", { name: "Plan another journey" }).click();
  await app.getByRole("button", { name: "Your location", exact: true }).click();
  await expect(app.getByRole("status")).toContainText("farther");
  await app.getByRole("button", { name: "Choose on map", exact: true }).click();
  const map = app.locator(".map-area");
  const size = await map.boundingBox();
  await map.click({ position: { x: size.width / 2, y: size.height * 0.7 } });
  await app
    .getByRole("button", { name: "Use this location", exact: true })
    .click();
  await app
    .getByRole("button", { name: "Start navigation", exact: true })
    .click();
  await expect(app.locator("[data-speed]")).not.toHaveText("0");
  expect(errors).toEqual([]);
});

test("expanded app tabs meet automated accessibility checks", async ({
  page,
}) => {
  const app = await openApp(page, 390, 844);
  const violations = [];
  for (const name of ["Map", "Home", "Sensors", "Profile"]) {
    await app.getByRole("button", { name, exact: true }).click();
    const result = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    violations.push(
      ...result.violations.map((v) => ({
        tab: name,
        rule: v.id,
        nodes: v.nodes.map((n) => ({
          target: n.target,
          issue: n.failureSummary,
        })),
      })),
    );
  }
  expect(violations).toEqual([]);
});

test("hero phone opens with scrolling animations enabled", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  const app = page.locator("gati-simulator");
  await expect(app.locator(".city-svg")).toBeVisible();
  await page
    .getByRole("button", { name: "Experience app", exact: true })
    .click();
  await expect(page.locator("#app-experience")).toBeVisible();
  await app.getByRole("button", { name: "Start drive", exact: true }).click();
  await expect(app.locator("[data-speed]")).not.toHaveText("0");
  await page.screenshot({ path: "test-results/app-map-mobile.png" });
});

test("timed blackout counts down, recovers, scores, and discards cancelled runs", async ({
  page,
}) => {
  await page.clock.install();
  const app = await openApp(page, 390, 844);
  await app
    .getByRole("button", { name: "Simulation Lab", exact: true })
    .click();
  await app
    .getByRole("button", { name: "Timed GPS loss test", exact: true })
    .click();
  await app.getByRole("button", { name: "10 s", exact: true }).click();
  await page.screenshot({ path: "test-results/app-timed-picker.png" });
  await app.getByRole("button", { name: "Start", exact: true }).click();
  await expect(app.locator("[data-countdown]")).toContainText("s left");
  await page.clock.runFor(10500);
  await expect(app.locator("[data-countdown]")).toContainText("Reacquiring");
  await page.clock.runFor(3500);
  await expect(app.locator(".sample-report")).toContainText(
    "GNSS outage · 10 s",
  );
  await expect(app.locator("[data-signal]")).toHaveText("GNSS locked");
  await page.screenshot({ path: "test-results/app-timed-result.png" });
  await app.getByRole("button", { name: "Run again", exact: true }).click();
  await app.getByRole("button", { name: "Start", exact: true }).click();
  await page.clock.runFor(1500);
  await app.getByRole("button", { name: "Cancel test", exact: true }).click();
  await app.getByRole("button", { name: "Profile", exact: true }).click();
  await app.getByRole("button", { name: /Outage Log 1 scored/ }).click();
  await expect(app.locator(".sample-report")).toHaveCount(1);
});

test("tunnel and canyon tests retain distinct speeds and stop only on request", async ({
  page,
}) => {
  await page.clock.install();
  const app = await openApp(page);
  await app
    .getByRole("button", { name: "Simulation Lab", exact: true })
    .click();
  await app.getByRole("button", { name: "Tunnel test", exact: true }).click();
  await page.clock.runFor(25000);
  await expect(app.locator("[data-speed]")).toHaveText("45");
  await expect(app.locator("[data-signal]")).toHaveText("Dead reckoning");
  await app.getByRole("button", { name: "End test", exact: true }).click();
  await app
    .getByRole("button", { name: "Simulation Lab", exact: true })
    .click();
  await app
    .getByRole("button", { name: "Urban canyon test", exact: true })
    .click();
  await expect(app.locator("[data-speed]")).toHaveText("30");
  await page.clock.runFor(5500);
  await expect(app.locator("[data-signal]")).toHaveText("GPS intermittent");
  await app.getByRole("button", { name: "End test", exact: true }).click();
  await expect(app.locator("[data-signal]")).toHaveText("GNSS locked");
});

test("profile tools complete local replays, marker matching, and exports", async ({
  page,
}) => {
  await page.clock.install();
  const app = await openApp(page, 390, 844);
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await app.getByRole("button", { name: "Profile", exact: true }).click();
  await app.getByRole("button", { name: /Outage Benchmark Score/ }).click();
  await app.getByRole("button", { name: "Run", exact: true }).click();
  await page.clock.runFor(2600);
  await expect(app.locator(".sample-report")).toBeVisible();
  await app.getByRole("button", { name: "Back", exact: true }).click();
  await app
    .getByRole("button", { name: /Fault Injection Lab Developer/ })
    .click();
  await app
    .getByRole("button", { name: "Gyro bias (+0.5 deg/s)", exact: true })
    .click();
  await app.getByRole("button", { name: "Run", exact: true }).click();
  await page.clock.runFor(2600);
  await expect(
    app.getByText("Heading error accumulates; no immediate alarm", {
      exact: true,
    }),
  ).toBeVisible();
  await app
    .getByRole("button", { name: "Run all faults", exact: true })
    .click();
  await page.clock.runFor(2600);
  await expect(app.locator(".card h2")).toHaveCount(9);
  const downloaded = page.waitForEvent("download");
  await app.getByRole("button", { name: "Export report", exact: true }).click();
  expect((await downloaded).suggestedFilename()).toBe("gatisaarth-tool.json");
  await app.getByRole("button", { name: "Back", exact: true }).click();
  await app
    .getByRole("button", { name: /Trusted Portal Scanner Offline/ })
    .click();
  await app
    .getByRole("button", { name: "Try an unrecognized marker", exact: true })
    .click();
  await page.clock.runFor(2600);
  await expect(app.getByRole("status")).toContainText("Marker not recognized");
  await app
    .getByRole("button", { name: "Match offline landmark", exact: true })
    .click();
  await page.clock.runFor(2600);
  await expect(app.getByRole("status")).toContainText("Trusted anchor matched");
  await app.getByRole("button", { name: "Back", exact: true }).click();
  await app
    .getByRole("button", { name: /Diagnostics Console Internal/ })
    .click();
  await app.getByRole("button", { name: "Pause", exact: true }).click();
  await expect(
    app.getByRole("button", { name: "Resume", exact: true }),
  ).toBeVisible();
  await app.getByRole("button", { name: "Clear log", exact: true }).click();
  await expect(app.locator(".event-log li")).toHaveCount(0);
  expect(errors).toEqual([]);
});

test("map drag, responsive rotation, and short keyboard-height screens remain usable", async ({
  page,
}) => {
  const app = await openApp(page, 390, 844);
  const map = app.locator(".map-area");
  const initial = await app.locator(".city-svg").getAttribute("viewBox");
  const rect = await map.boundingBox();
  await page.mouse.move(rect.x + rect.width * 0.4, rect.y + rect.height * 0.7);
  await page.mouse.down();
  await page.mouse.move(rect.x + rect.width * 0.6, rect.y + rect.height * 0.6, {
    steps: 8,
  });
  await page.mouse.up();
  expect(await app.locator(".city-svg").getAttribute("viewBox")).not.toBe(
    initial,
  );
  await app.getByRole("button", { name: "Recenter map", exact: true }).click();
  await expect(app.locator(".city-svg")).toHaveAttribute("viewBox", initial);
  const touch = await page.context().newCDPSession(page);
  const y = Math.round(rect.y + rect.height * 0.7);
  await touch.send("Input.dispatchTouchEvent", {
    type: "touchStart",
    touchPoints: [
      { x: 140, y, id: 1 },
      { x: 240, y, id: 2 },
    ],
  });
  await touch.send("Input.dispatchTouchEvent", {
    type: "touchMove",
    touchPoints: [
      { x: 110, y, id: 1 },
      { x: 270, y, id: 2 },
    ],
  });
  await touch.send("Input.dispatchTouchEvent", {
    type: "touchEnd",
    touchPoints: [],
  });
  expect(await app.locator(".city-svg").getAttribute("viewBox")).not.toBe(
    initial,
  );
  await touch.detach();
  await page.setViewportSize({ width: 844, height: 390 });
  await app
    .getByRole("button", { name: "Simulation Lab", exact: true })
    .click();
  await app
    .getByRole("button", { name: "Timed GPS loss test", exact: true })
    .click();
  await app.getByRole("button", { name: "60 s", exact: true }).click();
  await expect(
    app.getByRole("button", { name: "60 s", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await app.getByRole("button", { name: "Cancel", exact: true }).click();
  await page.setViewportSize({ width: 390, height: 450 });
  await app.getByRole("button", { name: "Home", exact: true }).click();
  await app
    .getByRole("button", { name: "Plan another journey", exact: true })
    .click();
  await app
    .getByRole("textbox", { name: "Destination", exact: true })
    .fill("Churchgate");
  await app
    .getByRole("button", { name: /Churchgate Station Churchgate/ })
    .click();
  await app
    .getByRole("button", { name: "Start navigation", exact: true })
    .click();
  await app.getByRole("button", { name: "Record drive", exact: true }).click();
  await expect(
    app.getByRole("button", { name: /Stop recording/ }),
  ).toBeVisible();
});

test("new tools and timed sheets retain accessible labels and contrast", async ({
  page,
}) => {
  test.setTimeout(60000);
  const app = await openApp(page, 390, 844);
  const findings = [];
  const audit = async (screen) => {
    const result = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    findings.push(
      ...result.violations.map((v) => ({
        screen,
        id: v.id,
        nodes: v.nodes.map((n) => ({
          target: n.target,
          issue: n.failureSummary,
        })),
      })),
    );
  };
  await app
    .getByRole("button", { name: "Simulation Lab", exact: true })
    .click();
  await audit("lab");
  await app
    .getByRole("button", { name: "Timed GPS loss test", exact: true })
    .click();
  await audit("duration picker");
  await app.getByRole("button", { name: "Cancel", exact: true }).click();
  await app.getByRole("button", { name: "Profile", exact: true }).click();
  for (const title of [
    /Trusted Portal Scanner Offline/,
    /Outage Benchmark Score/,
    /Fault Injection Lab Developer/,
    /Diagnostics Console Internal/,
  ]) {
    await app.getByRole("button", { name: title }).click();
    await audit(String(title));
    await app.getByRole("button", { name: "Back", exact: true }).click();
  }
  await app.getByRole("switch", { name: /Appearance/ }).click();
  await audit("light profile");
  await app.getByRole("button", { name: "Map", exact: true }).click();
  await audit("light map");
  expect(findings).toEqual([]);
});
