/**
 * Fulfill a POST API route with a streamed-style plaintext body.
 * Playwright delivers it as one response; the UI parses line-by-line the same way.
 */
async function mockPlainStream(page, pathSuffix, lines) {
  const body = `${lines.join("\n")}\n`;
  await page.route(`**${pathSuffix}`, async (route) => {
    if (route.request().method() !== "POST") {
      await route.continue();
      return;
    }
    await route.fulfill({
      status: 200,
      contentType: "text/plain; charset=utf-8",
      headers: {
        "Cache-Control": "no-cache",
      },
      body,
    });
  });
}

function createSuccessLines(accessKey = "ss://test-access-key#outline") {
  return [
    "PROGRESS|create|Creating instance cusor_instance…",
    "PROGRESS|created|Instance created",
    "PROGRESS|waiting|Waiting until instance is running…",
    "PROGRESS|running|Instance running",
    "PROGRESS|ip_create|Creating static IP…",
    "PROGRESS|ip_created|Static IP created",
    "PROGRESS|ip_attach|Attaching static IP…",
    "PROGRESS|ip_attached|Static IP attached",
    "PROGRESS|ssh|SSH ready",
    "PROGRESS|outline|Outline install finished",
    "PROGRESS|firewall|Lightsail firewall ports opened",
    "PROGRESS|outline_manager|Opening Outline Manager…",
    "PROGRESS|access_key|Access key fetched from Outline API",
    "PROGRESS|done|Outline access key ready",
    accessKey,
    JSON.stringify({ ok: true, accessKey }),
  ];
}

function createErrorLines(message = "AWS CLI command failed") {
  return [
    "PROGRESS|create|Creating instance cusor_instance…",
    `PROGRESS|error|${message}`,
    `ERROR: ${message}`,
    "FAILED (exit 1)",
  ];
}

function cleanupNotFoundLines() {
  return [
    JSON.stringify({
      ok: false,
      notFound: true,
      error: "Instance cusor_instance does not exist.",
      instance: "cusor_instance",
    }),
  ];
}

function cleanupSuccessLines() {
  return [
    "PROGRESS|stop|Stopping instance cusor_instance…",
    "PROGRESS|stopped|Instance stopped",
    "PROGRESS|delete_instance|Deleting instance…",
    "PROGRESS|instance_deleted|Instance deleted",
    "PROGRESS|delete_ip|Deleting static IP…",
    "PROGRESS|ip_deleted|Static IP deleted",
    "PROGRESS|done|Cleanup complete",
    JSON.stringify({
      ok: true,
      cleaned: true,
      instance: "cusor_instance",
      staticIp: "cusor_instance-ip",
    }),
  ];
}

module.exports = {
  mockPlainStream,
  createSuccessLines,
  createErrorLines,
  cleanupNotFoundLines,
  cleanupSuccessLines,
};
