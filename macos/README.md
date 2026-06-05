# Xerotier XIM on Apple Silicon

The Apple Silicon deployment of the Xerotier inference agent is a native macOS
**application** that installs, configures, and runs `xerotier-xim-agent` with
Metal-accelerated vLLM via
[vllm-metal](https://github.com/vllm-project/vllm-metal). It is the installer,
environment-prep, and control surface in one window, and everything runs as the
logged-in user (no admin password).

> **The app has moved.** It now lives in the main `xerotier` monorepo as a
> first-class target (`xerotier-desktop`), so it builds the agent it manages and
> links the cloud API client from the same package. The source and packaging
> that used to live here under `macos/app/` are gone — see
> `Sources/XerotierDesktop/` and `macos/packaging/` in the `xerotier` repo, and
> that repo's `macos/README.md` for build, packaging, and usage instructions.

There is intentionally **no container image** for this backend. vllm-metal
requires native macOS Metal access (MLX + Metal kernels, arm64 Python 3.12), and
Apple's `container` binary runs Linux guests with no GPU/Metal passthrough.

## Requirements

- Apple Silicon Mac (arm64) running macOS 15 (Sequoia) or newer.
- A join key from the dashboard: **Infrastructure → Agents → Generate Join Key**.

(`curl`, `uv`, and Python 3.12 are provisioned automatically on first run.)

## Install

1. Download the latest **`Xerotier-<version>.dmg`** from the
   [Releases page](https://github.com/cloudnull/xerotier-public/releases/latest)
   and drag **Xerotier.app** into Applications.
2. Open **Xerotier** and go to **Setup**.
3. Confirm the host preflight passes, paste your join key, and click
   **Install & Start**.

The app then provisions Python 3.12 via `uv`, installs vllm-metal, renders the
vLLM wrapper, enrolls, and runs the XIM agent **in-process** (the agent is linked
into the app — there is no separate binary or launchd service). A **Cloud** pane
manages the project's endpoints and models via the Xerotier API.

> Because the agent runs in-process, it serves only while the app is open;
> quitting the app stops the worker. Logs stream live in the app's **Logs** pane.
