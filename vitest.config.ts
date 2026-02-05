import { defineConfig } from "vitest/config";

defineConfig({
  test: {
    testTimeout: 30_000, // 30 seconds, which is needed for the installer tests that involve downloading and installing Wasp.
  },
});
