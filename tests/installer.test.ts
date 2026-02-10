import { $ } from "execa";
import assert from "node:assert/strict";
import * as fs from "node:fs/promises";
import * as path from "node:path";
import { temporaryDirectoryTask } from "tempy";
import { describe, expect, it } from "vitest";
import "./matchers";

const shell = process.env.TEST_SHELL ?? process.env.SHELL!;
assert(shell, "TEST_SHELL or SHELL environment variables are not set");
const installerPath = path.resolve(import.meta.dirname, "../installer.sh");

describe("installer", () => {
  it.each(["0.18.0", "0.20.1"])("installs specific version (%s)", (version) =>
    createTemporaryInstallerTestEnvironment(
      async ({ HOME, waspBinary, waspVersionDir }) => {
        await $(shell, [installerPath, "-v", version], { env: { HOME } });

        expect(waspBinary).toBeExecutable();
        expect(waspVersionDir(version)).toBeDirectory();

        expect(await $(waspBinary, ["version"])).toMatchObject({
          stdout: expect.stringContaining(version),
        });
      },
    ),
  );

  it("fails when version is not specified", () =>
    createTemporaryInstallerTestEnvironment(async ({ HOME, waspBinary }) => {
      await expect(
        $(shell, [installerPath], { env: { HOME } }),
      ).rejects.toMatchObject({
        exitCode: 1,
        stderr: expect.stringContaining("A version argument is required."),
      });

      expect(waspBinary).not.toExist();
    }));

  it.each(["0.21", "0.22", "1.0", "1.1"])(
    "rejects installing newer version (%s)",
    (version) =>
      createTemporaryInstallerTestEnvironment(async ({ HOME, waspBinary }) => {
        await expect(
          $(shell, [installerPath, "-v", version], { env: { HOME } }),
        ).rejects.toMatchObject({
          exitCode: 1,
          stderr: expect.stringContaining(
            "Wasp version 0.21 and later must be installed via npm.",
          ),
        });

        expect(waspBinary).not.toExist();
      }),
  );

  it("rejects installing when the npm marker file is present", () =>
    createTemporaryInstallerTestEnvironment(
      async ({ HOME, npmMarker, waspBinary }) => {
        await fs.mkdir(path.dirname(npmMarker), { recursive: true });
        await fs.writeFile(npmMarker, "");

        await expect(
          $(shell, [installerPath, "-v", "0.18.0"], { env: { HOME } }),
        ).rejects.toMatchObject({
          exitCode: 1,
          stderr: expect.stringContaining(
            "You are already using Wasp through npm.",
          ),
        });

        expect(waspBinary).not.toExist();
      },
    ));
});

describe("migrator", () => {
  it("migrates from old version to new version", () =>
    createTemporaryInstallerTestEnvironment(
      async ({ HOME, waspVersionDir, waspBinary, npmMarker }) => {
        const oldVersionPath = waspVersionDir("0.18.0");
        await fs.mkdir(oldVersionPath, { recursive: true });

        await $(shell, [installerPath, "migrate-to-npm"], { env: { HOME } });

        expect(oldVersionPath).not.toExist();
        expect(npmMarker).toBeFile();
      },
    ));
});

async function createTemporaryInstallerTestEnvironment<T>(
  fn: (paths: ReturnType<typeof calculateWaspPaths>) => Promise<T>,
) {
  return await temporaryDirectoryTask(async (tmpDir) =>
    fn(calculateWaspPaths(tmpDir)),
  );
}

function calculateWaspPaths(HOME: string) {
  const waspBinary = path.join(HOME, ".local/bin/wasp");
  const waspDataDir = path.join(HOME, ".local/share/wasp-lang");
  const waspVersionDir = (version: string) => path.join(waspDataDir, version);
  const npmMarker = path.join(waspDataDir, ".uses-npm");

  return { HOME, waspBinary, waspDataDir, waspVersionDir, npmMarker };
}
