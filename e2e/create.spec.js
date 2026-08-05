const { test, expect } = require("@playwright/test");
const {
  mockPlainStream,
  createSuccessLines,
  createErrorLines,
} = require("./helpers");

test.describe("create flow", () => {
  test("streams progress and shows access key on success", async ({ page }) => {
    const accessKey = "ss://e2e-success-key#outline";
    await mockPlainStream(page, "/api/create-instance", createSuccessLines(accessKey));
    await page.goto("/");

    await page.getByRole("button", { name: "Create cusor_instance" }).click();

    const modal = page.locator("#progress-modal");
    await expect(modal).toBeVisible();
    await expect(page.locator("#progress-title")).toHaveText("Provisioning progress");
    await expect(page.locator("#progress-steps li")).toHaveCount(14);

    await expect(page.locator('#progress-steps li[data-step="done"]')).toHaveAttribute(
      "data-state",
      "done",
    );
    await expect(page.locator("#progress-detail")).toHaveText("Access key ready");
    await expect(page.locator("#progress-json")).toBeVisible();
    await expect(page.locator("#progress-json")).toHaveText(accessKey);
    await expect(page.locator("#progress-close")).toBeVisible();

    await page.locator("#progress-close").click();
    await expect(modal).toBeHidden();
  });

  test("shows error details when create fails", async ({ page }) => {
    const message = "Bundle not available in this zone";
    await mockPlainStream(page, "/api/create-instance", createErrorLines(message));
    await page.goto("/");

    await page.getByRole("button", { name: "Create cusor_instance" }).click();

    await expect(page.locator("#progress-modal")).toBeVisible();
    await expect(page.locator("#progress-detail")).toHaveAttribute("data-kind", "error");
    await expect(page.locator("#progress-error")).toBeVisible();
    await expect(page.locator("#progress-error")).toContainText(message);
    await expect(page.locator("#progress-json")).toBeHidden();
    await expect(page.locator("#progress-close")).toBeVisible();
  });
});
