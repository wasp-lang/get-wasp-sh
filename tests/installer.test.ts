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
  it("installs specific version", () =>
    createInstallerEnvironment(async ({ HOME, waspBinary, waspVersionDir }) => {
      await $(shell, [installerPath, "-v", "0.18.0"], { env: { HOME } });

      expect(waspBinary).toBeExecutable();
      expect(waspVersionDir("0.18.0")).toBeDirectory();

      expect(await $(waspBinary, ["version"])).toMatchObject({
        stdout: expect.stringContaining("0.18.0"),
      });
    }));

  it("fails when version is not specified", () =>
    createInstallerEnvironment(async ({ HOME, waspBinary }) => {
      await expect(
        $(shell, [installerPath], { env: { HOME } }),
      ).rejects.toMatchObject({
        exitCode: 1,
        stderr: expect.stringContaining("A version argument is required."),
      });

      expect(waspBinary).not.toExist();
    }));

  it.each(["0.21", "0.22", "1.0", "1.1"])(
    "rejects installing newer versions (%s)",
    (version) =>
      createInstallerEnvironment(async ({ HOME, waspBinary }) => {
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
    createInstallerEnvironment(async ({ HOME, npmMarker, waspBinary }) => {
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
    }));
});

describe("migrator", () => {
  it("migrates from old version to new version", () =>
    createInstallerEnvironment(
      async ({ HOME, waspVersionDir, waspBinary, npmMarker }) => {
        const oldVersionPath = waspVersionDir("0.18.0");
        await fs.mkdir(oldVersionPath, { recursive: true });

        await $(shell, [installerPath, "migrate-to-npm"], { env: { HOME } });

        expect(waspBinary).not.toExist();
        expect(oldVersionPath).not.toExist();

        expect(npmMarker).toBeFile();
      },
    ));
});

async function createInstallerEnvironment(
  fn: (paths: ReturnType<typeof calculatePaths>) => any,
) {
  return await temporaryDirectoryTask(async (tmpDir) =>
    fn(calculatePaths(tmpDir)),
  );
}

function calculatePaths(HOME: string) {
  const waspBinary = path.join(HOME, ".local/bin/wasp");
  const waspDataDir = path.join(HOME, ".local/share/wasp-lang");
  const waspVersionDir = (version: string) => path.join(waspDataDir, version);
  const npmMarker = path.join(waspDataDir, ".uses-npm");

  return { HOME, waspBinary, waspDataDir, waspVersionDir, npmMarker };
}
