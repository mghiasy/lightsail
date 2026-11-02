const { test, expect } = require("@playwright/test");

test.describe("home page", () => {
  test("shows brand, headline, and action buttons", async ({ page }) => {
    await page.goto("/");

    await expect(page.locator(".brand")).toHaveText("Lightsail");
    await expect(page.locator(".headline")).toHaveText("Provision Lightsail");
    await expect(page.getByRole("button", { name: "Create cusor_instance" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Clean up" })).toBeVisible();
    await expect(page.locator("#progress-modal")).toBeHidden();
    await expect(page.locator("#message-modal")).toBeHidden();
  });
});
