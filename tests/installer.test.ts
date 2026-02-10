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
      createTemporaryInstallerTestEnvironment(
        async ({ HOME, installerWaspBinaryFile, installerWaspVersionDir }) => {
          await $(shell, [installerPath, "-v", version], { env: { HOME } });

          expect(installerWaspBinaryFile).toBeExecutable();
          expect(installerWaspVersionDir(version)).toBeDirectory();

          expect(await $(installerWaspBinaryFile, ["version"])).toMatchObject({
            stdout: expect.stringContaining(version),
          });
        },
      ),
  );

  it("fails when version is not specified", () =>
    createTemporaryInstallerTestEnvironment(
      async ({ HOME, installerWaspBinaryFile }) => {
        await expect(
          $(shell, [installerPath], { env: { HOME } }),
        ).rejects.toMatchObject({
          exitCode: 1,
          stderr: expect.stringContaining("A version argument is required."),
        });

        expect(installerWaspBinaryFile).not.toExist();
      },
    ));

  it.each(["0.21", "0.22", "1.0", "1.1"])(
    "rejects installing newer version (%s)",
    (version) =>
      createTemporaryInstallerTestEnvironment(
        async ({ HOME, installerWaspBinaryFile }) => {
          await expect(
            $(shell, [installerPath, "-v", version], { env: { HOME } }),
          ).rejects.toMatchObject({
            exitCode: 1,
            stderr: expect.stringContaining(
              "Wasp version 0.21 and later must be installed via npm.",
            ),
          });

          expect(installerWaspBinaryFile).not.toExist();
        },
      ),
  );

  it("rejects installing when the npm marker file is present", () =>
    createTemporaryInstallerTestEnvironment(
      async ({ HOME, npmMarkerFile, installerWaspBinaryFile }) => {
        await fs.mkdir(path.dirname(npmMarkerFile), { recursive: true });
        await fs.writeFile(npmMarkerFile, "");

        await expect(
          $(shell, [installerPath, "-v", "0.18.0"], { env: { HOME } }),
        ).rejects.toMatchObject({
          exitCode: 1,
          stderr: expect.stringContaining(
            "You are already using Wasp through npm.",
          ),
        });

        expect(installerWaspBinaryFile).not.toExist();
      },
    ));
});

describe("migrator", () => {
  it("migrates from old version to new version", () =>
    createTemporaryInstallerTestEnvironment(
      async ({ HOME, installerWaspVersionDir, npmMarkerFile }) => {
        const oldVersionPath = installerWaspVersionDir("0.18.0");
        await fs.mkdir(oldVersionPath, { recursive: true });

        await $(shell, [installerPath, "migrate-to-npm"], { env: { HOME } });

        expect(oldVersionPath).not.toExist();
        expect(npmMarkerFile).toBeFile();
      },
    ));

  it("refuses to migrate when an npm marker file is already present", () =>
    createTemporaryInstallerTestEnvironment(async ({ HOME, npmMarkerFile }) => {
      await fs.mkdir(path.dirname(npmMarkerFile), { recursive: true });
      await fs.writeFile(npmMarkerFile, "");

      await expect(
        $(shell, [installerPath, "migrate-to-npm"], { env: { HOME } }),
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
    createTemporaryInstallerTestEnvironment(
      async ({ HOME, installerWaspBinaryFile, npmMarkerFile }) => {
        await $(shell, [installerPath, "-v", "0.18.0"], { env: { HOME } });

        await expect(
          $(
            "npm",
            [
              "install",
              "-g",
              // TODO: Update this to the published package once this PR is merged and published
              "https://pkg.pr.new/@wasp.sh/wasp-cli@3711",
            ],
            { env: { HOME } },
          ),
        ).rejects.toMatchObject({
          exitCode: 1,
          stderr: expect.stringContaining(
            "Detected an existing installer-based Wasp installation.",
          ),
        });

        expect(installerWaspBinaryFile).toBeExecutable();
        expect(npmMarkerFile).not.toExist();
      },
    ));

  it("installs when the installer was used and then migrated", () =>
    createTemporaryInstallerTestEnvironment(
      async ({ HOME, installerWaspBinaryFile, npmMarkerFile }) => {
        await $(shell, [installerPath, "-v", "0.18.0"], { env: { HOME } });
        await $(shell, [installerPath, "migrate-to-npm"], { env: { HOME } });

        await $(
          "npm",
          [
            "install",
            "-g",
            // TODO: Update this to the published package once this PR is merged and published
            "https://pkg.pr.new/@wasp.sh/wasp-cli@3711",
          ],
          { env: { HOME } },
        );

        expect(installerWaspBinaryFile).not.toExist();
        expect(npmMarkerFile).toBeFile();
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
  const installerWaspBinaryFile = path.join(HOME, ".local/bin/wasp");
  const waspDataDir = path.join(HOME, ".local/share/wasp-lang");
  const installerWaspVersionDir = (version: string) =>
    path.join(waspDataDir, version);
  const npmMarkerFile = path.join(waspDataDir, ".uses-npm");

  return {
    HOME,
    installerWaspBinaryFile,
    waspDataDir,
    installerWaspVersionDir,
    npmMarkerFile,
  };
}
