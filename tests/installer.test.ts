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
  it.each(["0.18.0", "0.20.1"])(
    "installs specific supported version (%s)",
    (version) =>
      createTemporaryInstallerTestEnvironment(async ({ paths, env }) => {
        await $(shell, [installerPath, "-v", version], { env });

        expect(paths.installer.waspBinaryFile).toBeExecutable();
        expect(paths.installer.waspVersionDir(version)).toBeDirectory();

        expect(
          await $(paths.installer.waspBinaryFile, ["version"]),
        ).toMatchObject({
          stdout: expect.stringContaining(version),
        });
      }),
  );

  it("fails when version is not specified", () =>
    createTemporaryInstallerTestEnvironment(async ({ paths, env }) => {
      await expect($(shell, [installerPath], { env })).rejects.toMatchObject({
        exitCode: 1,
        stderr: expect.stringContaining("A version argument is required."),
      });

      expect(paths.installer.waspBinaryFile).not.toExist();
    }));

  it.each(["0.21", "0.22", "1.0", "1.1"])(
    "rejects installing newer version (%s)",
    (version) =>
      createTemporaryInstallerTestEnvironment(async ({ paths, env }) => {
        await expect(
          $(shell, [installerPath, "-v", version], { env }),
        ).rejects.toMatchObject({
          exitCode: 1,
          stderr: expect.stringContaining(
            "Wasp version 0.21 and later must be installed via npm.",
          ),
        });

        expect(paths.installer.waspBinaryFile).not.toExist();
      }),
  );

  it("rejects installing when the npm marker file is present", () =>
    createTemporaryInstallerTestEnvironment(async ({ paths, env }) => {
      await fs.mkdir(path.dirname(paths.npm.markerFile), { recursive: true });
      await fs.writeFile(paths.npm.markerFile, "");

      await expect(
        $(shell, [installerPath, "-v", "0.18.0"], { env }),
      ).rejects.toMatchObject({
        exitCode: 1,
        stderr: expect.stringContaining(
          "You are already using Wasp through npm.",
        ),
      });

      expect(paths.installer.waspBinaryFile).not.toExist();
    }));
});

describe("migrator", () => {
  it("migrates from old version to new version", () =>
    createTemporaryInstallerTestEnvironment(async ({ paths, env }) => {
      const oldVersionPath = paths.installer.waspVersionDir("0.18.0");
      await fs.mkdir(oldVersionPath, { recursive: true });

      await $(shell, [installerPath, "migrate-to-npm"], { env });

      expect(oldVersionPath).not.toExist();
      expect(paths.npm.markerFile).toBeFile();
    }));

  it("refuses to migrate when an npm marker file is already present", () =>
    createTemporaryInstallerTestEnvironment(async ({ paths, env }) => {
      await fs.mkdir(path.dirname(paths.npm.markerFile), { recursive: true });
      await fs.writeFile(paths.npm.markerFile, "");

      await expect(
        $(shell, [installerPath, "migrate-to-npm"], { env }),
      ).rejects.toMatchObject({
        exitCode: 1,
        stderr: expect.stringContaining(
          "You are already using Wasp through npm.",
        ),
      });
    }));
});

describe("npm package", () => {
  it("rejects installing when the installer was used", () =>
    createTemporaryInstallerTestEnvironment(async ({ paths, env }) => {
      await $(shell, [installerPath, "-v", "0.18.0"], { env });

      await expect(
        $(
          "npm",
          [
            "install",
            "-g",
            // TODO: Update this to the published package once this PR is merged and published
            "https://pkg.pr.new/@wasp.sh/wasp-cli@3711",
          ],
          { env },
        ),
      ).rejects.toMatchObject({
        exitCode: 1,
        stderr: expect.stringContaining(
          "Detected an existing legacy Wasp installation.",
        ),
      });

      expect(paths.installer.waspBinaryFile).toBeExecutable();
      expect(paths.npm.markerFile).not.toExist();
      expect(paths.npm.waspBinaryFile).not.toExist();
    }));

  it("installs when the installer was used and then migrated", () =>
    createTemporaryInstallerTestEnvironment(async ({ paths, env }) => {
      await $(shell, [installerPath, "-v", "0.18.0"], { env });
      await $(shell, [installerPath, "migrate-to-npm"], { env });

      await $(
        "npm",
        [
          "install",
          "-g",
          // TODO: Update this to the published package once this PR is merged and published
          "https://pkg.pr.new/@wasp.sh/wasp-cli@3711",
        ],
        { env },
      );

      expect(paths.installer.waspBinaryFile).not.toExist();
      expect(paths.npm.markerFile).toBeFile();
      expect(paths.npm.waspBinaryFile).toBeExecutable();
    }));
});

async function createTemporaryInstallerTestEnvironment<T>(
  fn: (paths: ReturnType<typeof calculateWaspEnvironment>) => Promise<T>,
) {
  return await temporaryDirectoryTask(async (tmpDir) =>
    fn(calculateWaspEnvironment(tmpDir)),
  );
}

function calculateWaspEnvironment(HOME: string) {
  const waspDataDir = path.join(HOME, ".local/share/wasp-lang");
  const npmPrefix = path.join(HOME, ".local/share/npm");

  return {
    env: {
      HOME,
      npm_config_prefix: npmPrefix,
    },
    paths: {
      waspDataDir,
      installer: {
        waspBinaryFile: path.join(HOME, ".local/bin/wasp"),
        waspVersionDir: (version: string) => path.join(waspDataDir, version),
      },
      npm: {
        markerFile: path.join(waspDataDir, ".uses-npm"),
        waspBinaryFile: path.join(npmPrefix, "bin/wasp"),
      },
    },
  };
}
