import * as fs from "node:fs/promises";
import "vitest";
import { expect } from "vitest";

interface CustomMatchers<R = unknown> {
  toExist(): Promise<R>;
  toBeFile(): Promise<R>;
  toBeExecutable(): Promise<R>;
  toBeDirectory(): Promise<R>;
}

declare module "vitest" {
  interface Matchers<T = any> extends CustomMatchers<T> {}
}

expect.extend({
  async toExist(received: string) {
    const exists = await fs.access(received).then(
      () => true,
      () => false,
    );

    return {
      pass: exists,
      message: () => `expected ${received} to${this.isNot ? " not" : ""} exist`,
    };
  },

  async toBeFile(received: string) {
    const isFile = await fs.stat(received).then(
      (stats) => stats.isFile(),
      () => false,
    );

    return {
      pass: isFile,
      message: () =>
        `expected ${received} to${this.isNot ? " not" : ""} be a file`,
    };
  },

  async toBeExecutable(received: string) {
    const isExecutable = await fs.access(received, fs.constants.X_OK).then(
      () => true,
      () => false,
    );

    return {
      pass: isExecutable,
      message: () =>
        `expected ${received} to${this.isNot ? " not" : ""} be executable`,
    };
  },

  async toBeDirectory(received: string) {
    const isDirectory = await fs.stat(received).then(
      (stats) => stats.isDirectory(),
      () => false,
    );

    return {
      pass: isDirectory,
      message: () =>
        `expected ${received} to${this.isNot ? " not" : ""} be a directory`,
    };
  },
});
