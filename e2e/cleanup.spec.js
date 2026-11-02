const { test, expect } = require("@playwright/test");
const {
  mockPlainStream,
  cleanupNotFoundLines,
  cleanupSuccessLines,
} = require("./helpers");

test.describe("cleanup flow", () => {
  test("shows popup when instance does not exist", async ({ page }) => {
    await mockPlainStream(page, "/api/cleanup-instance", cleanupNotFoundLines());
    await page.goto("/");

    await page.getByRole("button", { name: "Clean up" }).click();

    const messageModal = page.locator("#message-modal");
    await expect(messageModal).toBeVisible();
    await expect(page.locator("#message-title")).toHaveText("Cleanup");
    await expect(page.locator("#message-body")).toHaveText(
      "Instance cusor_instance does not exist.",
    );
    await expect(page.locator("#progress-modal")).toBeHidden();

    await page.locator("#message-close").click();
    await expect(messageModal).toBeHidden();
  });

  test("streams cleanup progress on success", async ({ page }) => {
    await mockPlainStream(page, "/api/cleanup-instance", cleanupSuccessLines());
    await page.goto("/");

    await page.getByRole("button", { name: "Clean up" }).click();

    const modal = page.locator("#progress-modal");
    await expect(modal).toBeVisible();
    await expect(page.locator("#progress-title")).toHaveText("Cleanup progress");
    await expect(page.locator("#progress-steps li")).toHaveCount(7);
    await expect(page.locator('#progress-steps li[data-step="done"]')).toHaveAttribute(
      "data-state",
      "done",
    );
    await expect(page.locator("#progress-detail")).toHaveText("Cleanup complete");
    await expect(page.locator("#progress-close")).toBeVisible();
  });
});
