> [!IMPORTANT]
> This script is no longer the recommended way to install Wasp on your system.
> Check [the Legacy Installer guide](https://wasp.sh/docs/guides/legacy/installer) for migration instructions.

# get-wasp

This repo is used as a way to publish static wasp resources, primarily installer script.

Anything that you put here in master branch will be available under get.wasp.sh/ (via Github Pages).

Therefore, installer.sh will be available as get.wasp.sh/installer.sh .

## Development

Test with `dash installer.sh`, to ensure it works on variety with `sh`, not just `bash` (dash is implementation of `sh`, so simpler than `bash`, and is a default shell on ubuntu).

Also, use shellcheck to check the code: `shellcheck installer.sh`.
