#!/bin/bash
# SPDX-License-Identifier: MIT
# Xerotier XIM + vllm-metal management script (macOS / Apple Silicon).
#
# Install (default): installs vllm-metal into ~/.venv-vllm-metal, downloads the
# prebuilt xerotier-xim-agent into ~/.local/bin, installs the HuggingFace compat
# shim into the venv, renders the vLLM wrapper / entrypoint / LaunchAgent from
# templates, and starts the per-user LaunchAgent. Also manages the service:
# --start, --stop, --uninstall. There is no container image: vllm-metal requires
# native macOS Metal access, which Apple `container` Linux VMs do not provide.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="${REPO_ROOT}/macos"
HF_COMPAT_SRC="${DEPLOY_DIR}/xerotier_hf_compat.py"
RELEASE_REPO="cloudnull/xerotier-public"

VENV="${HOME}/.venv-vllm-metal"
BIN_DIR="${HOME}/.local/bin"
LOG_DIR="${HOME}/Library/Logs/xerotier"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_DST="${LAUNCH_AGENTS_DIR}/com.xerotier.xim-agent.plist"
LABEL="com.xerotier.xim-agent"

JOIN_KEY=""
REINSTALL_VLLM=0
NO_START=0
DO_UNINSTALL=0
PURGE=0
PRE_RELEASE=0
DO_START=0
DO_STOP=0

log() { printf '[xim-metalctl] %s\n' "$*"; }
die() { printf '[xim-metalctl] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: xim-metalctl.sh [options]

Options:
  --join-key <key>    Enrollment join key (baked into the LaunchAgent env).
  --pre-release       Allow installing the agent from a prerelease GitHub
                      release (default: stable releases only).
  --reinstall-vllm    Force reinstall of vllm-metal even if already present.
  --no-start          Render artifacts but do not load the LaunchAgent.
  --start             Enable and start the XIM LaunchAgent (now and at login).
  --stop              Stop and disable the XIM LaunchAgent.
  --uninstall         Bootout the LaunchAgent and remove rendered files.
  --purge             With --uninstall, also remove the agent binary and venv.
  -h, --help          Show this help.
EOF
}

preflight() {
    [[ "$(uname -s)" == "Darwin" ]] || die "macOS only. Detected: $(uname -s)."
    [[ "$(uname -m)" == "arm64" ]] || die "Apple Silicon (arm64) required. Detected: $(uname -m)."
    # A python3 (any version) is only needed by uv and the upstream installer's
    # JSON parsing; the vllm-metal venv gets its own pinned interpreter below.
    command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH."
    command -v curl >/dev/null 2>&1 || die "curl not found on PATH."
    [[ -f "${HF_COMPAT_SRC}" ]] || die "HF compat shim missing at ${HF_COMPAT_SRC}."
    if ! command -v uv >/dev/null 2>&1; then
        log "uv not found; installing via the official installer..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="${HOME}/.local/bin:${PATH}"
        command -v uv >/dev/null 2>&1 || [[ -x "${HOME}/.local/bin/uv" ]] || die "uv install failed."
    fi
    # vllm-metal requires exactly Python 3.12, and its upstream installer creates
    # the venv with `uv venv --python 3.12 --seed`. The host's default python3
    # version is therefore irrelevant (it may be 3.13+); we only need to
    # guarantee uv can supply a 3.12. Provision a uv-managed 3.12 now (idempotent;
    # downloads only if one is not already available) so the venv build below
    # cannot fall back to an unsupported interpreter.
    log "Ensuring a supported Python (3.12) is available via uv..."
    uv python install 3.12 || die "Could not provision Python 3.12 via uv (required by vllm-metal)."
    log "Preflight OK: arm64 macOS, curl present, Python 3.12 available via uv."
}

install_vllm_metal() {
    if [[ "${REINSTALL_VLLM}" -eq 0 && -x "${VENV}/bin/vllm" ]]; then
        log "vllm-metal already present at ${VENV} (use --reinstall-vllm to force)."
        return
    fi
    log "Installing vllm-metal into ${VENV} (builds vLLM core from source; this can take a while)..."
    curl -fsSL https://raw.githubusercontent.com/vllm-project/vllm-metal/main/install.sh | bash
    [[ -x "${VENV}/bin/vllm" ]] || die "vllm-metal install did not produce ${VENV}/bin/vllm."
    log "vllm-metal installed."
}

fetch_agent() {
    # Release assets are named "<product>-<uname -sm joined by '->'", per
    # .github/workflows/binary-build.yml. On Apple Silicon `uname -sm` is
    # "Darwin arm64", so the asset resolves to xerotier-xim-agent-Darwin-arm64.
    local asset
    asset="xerotier-xim-agent-$(uname -sm | sed -e 's@ @-@g' -e 's@/@-@g')"

    # Resolve the asset URL via the releases API rather than the
    # /releases/latest/download redirect: that redirect targets only the latest
    # *stable* release and 404s when the repo has published only prereleases.
    # Walk the releases list (newest first) for the newest stable release that
    # carries the asset; with --pre-release, fall back to the newest prerelease.
    # Drafts are never visible to unauthenticated requests.
    local api releases_json url
    api="https://api.github.com/repos/${RELEASE_REPO}/releases"
    log "Resolving prebuilt ${asset} from ${RELEASE_REPO} releases..."
    releases_json="$(curl -fsSL "${api}")" \
        || die "Failed to query the releases API at ${api} (network or GitHub rate limit)."
    # shellcheck disable=SC2016
    url="$(printf '%s' "${releases_json}" \
        | XEROTIER_ASSET="${asset}" XEROTIER_ALLOW_PRERELEASE="${PRE_RELEASE}" python3 -c '
import json, os, sys
asset = os.environ["XEROTIER_ASSET"]
allow_prerelease = os.environ.get("XEROTIER_ALLOW_PRERELEASE") == "1"
try:
    rels = json.load(sys.stdin)
except Exception:
    sys.exit(0)
def find(include_prerelease):
    for rel in rels:
        if rel.get("draft"):
            continue
        if not include_prerelease and rel.get("prerelease"):
            continue
        for a in rel.get("assets", []):
            if a.get("name") == asset:
                return a.get("browser_download_url", "")
    return ""
url = find(False)
if not url and allow_prerelease:
    url = find(True)
sys.stdout.write(url)
')"
    if [[ -z "${url}" ]]; then
        if [[ "${PRE_RELEASE}" -eq 1 ]]; then
            die "No release asset named ${asset} found in any published release (stable or prerelease) at https://github.com/${RELEASE_REPO}/releases."
        else
            die "No stable release asset named ${asset} found at https://github.com/${RELEASE_REPO}/releases. Pass --pre-release to install from a prerelease."
        fi
    fi

    log "Downloading ${asset} from ${url}..."
    mkdir -p "${BIN_DIR}"
    if ! curl -fL "${url}" -o "${BIN_DIR}/xerotier-xim-agent"; then
        rm -f "${BIN_DIR}/xerotier-xim-agent"
        die "Failed to download ${asset} from ${url}."
    fi
    chmod 0755 "${BIN_DIR}/xerotier-xim-agent"
    # A downloaded binary may carry a quarantine xattr; clear it so launchd can
    # exec it without a Gatekeeper prompt. Best-effort (xattr/attr may be absent).
    xattr -d com.apple.quarantine "${BIN_DIR}/xerotier-xim-agent" 2>/dev/null || true
    log "Installed agent to ${BIN_DIR}/xerotier-xim-agent."
}

install_shim() {
    local site
    site="$("${VENV}/bin/python3" -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
    [[ -n "${site}" && -d "${site}" ]] || die "Could not resolve venv site-packages."
    install -m 0644 "${HF_COMPAT_SRC}" "${site}/xerotier_hf_compat.py"
    printf 'import xerotier_hf_compat\n' > "${site}/xerotier_hf_compat.pth"
    log "Installed HF compat shim into ${site}."
}

render_artifacts() {
    mkdir -p "${BIN_DIR}" "${LOG_DIR}" "${LAUNCH_AGENTS_DIR}"

    # Escape sed-significant characters in the (untrusted) join key.
    local join_esc
    join_esc="$(printf '%s' "${JOIN_KEY}" | sed -e 's/\\/\\\\/g' -e 's/[&|]/\\&/g')"

    sed "s|@VENV_PYTHON@|${VENV}/bin/python3|g" \
        "${DEPLOY_DIR}/xerotier-vllm.template" > "${BIN_DIR}/xerotier-vllm"
    chmod 0755 "${BIN_DIR}/xerotier-vllm"

    install -m 0755 "${DEPLOY_DIR}/entrypoint-agent-macos.sh" "${BIN_DIR}/xerotier-xim-entrypoint"

    local plist_tmp
    plist_tmp="$(mktemp "${PLIST_DST}.XXXXXX")"
    chmod 0600 "${plist_tmp}"
    sed -e "s|@ENTRYPOINT@|${BIN_DIR}/xerotier-xim-entrypoint|g" \
        -e "s|@HOME@|${HOME}|g" \
        -e "s|@VENV_BIN@|${VENV}/bin|g" \
        -e "s|@JOIN_KEY@|${join_esc}|g" \
        "${DEPLOY_DIR}/com.xerotier.xim-agent.plist.template" > "${plist_tmp}"
    mv "${plist_tmp}" "${PLIST_DST}"
    log "Rendered wrapper, entrypoint, and LaunchAgent."
}

start_agent() {
    [[ -f "${PLIST_DST}" ]] \
        || die "LaunchAgent not found at ${PLIST_DST}. Run xim-metalctl.sh (no action) first to install."
    local uid; uid="$(id -u)"
    # Clear any prior disabled state (from --stop) before loading, otherwise
    # bootstrap is refused for a disabled service. Then reload cleanly.
    launchctl enable "gui/${uid}/${LABEL}" 2>/dev/null || true
    launchctl bootout "gui/${uid}/${LABEL}" 2>/dev/null || true
    launchctl bootstrap "gui/${uid}" "${PLIST_DST}"
    log "Started ${LABEL} (runs now and at login). Logs: ${LOG_DIR}/"
}

stop_agent() {
    local uid; uid="$(id -u)"
    # bootout stops it now; disable keeps it from relaunching at next login.
    launchctl bootout "gui/${uid}/${LABEL}" 2>/dev/null || true
    launchctl disable "gui/${uid}/${LABEL}" 2>/dev/null || true
    log "Stopped ${LABEL} (will not run until 'xim-metalctl.sh --start')."
}

uninstall() {
    local uid; uid="$(id -u)"
    launchctl bootout "gui/${uid}/${LABEL}" 2>/dev/null || true
    rm -f "${PLIST_DST}" "${BIN_DIR}/xerotier-vllm" "${BIN_DIR}/xerotier-xim-entrypoint"
    log "Removed LaunchAgent and rendered files."
    if [[ "${PURGE}" -eq 1 ]]; then
        rm -f "${BIN_DIR}/xerotier-xim-agent"
        rm -rf "${VENV}"
        log "Purged agent binary and venv."
    fi
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --join-key)
                [[ $# -ge 2 ]] || die "--join-key requires an argument."
                JOIN_KEY="$2"; shift 2 ;;
            --join-key=*) JOIN_KEY="${1#*=}"; shift ;;
            --pre-release) PRE_RELEASE=1; shift ;;
            --reinstall-vllm) REINSTALL_VLLM=1; shift ;;
            --no-start) NO_START=1; shift ;;
            --start) DO_START=1; shift ;;
            --stop) DO_STOP=1; shift ;;
            --uninstall) DO_UNINSTALL=1; shift ;;
            --purge) PURGE=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown argument: $1 (see --help)" ;;
        esac
    done

    if [[ "${PURGE}" -eq 1 && "${DO_UNINSTALL}" -eq 0 ]]; then
        die "--purge requires --uninstall."
    fi

    # --uninstall/--start/--stop are mutually exclusive service actions that
    # short-circuit the install flow.
    if (( DO_UNINSTALL + DO_START + DO_STOP > 1 )); then
        die "Choose only one of --uninstall, --start, --stop."
    fi

    if [[ "${DO_UNINSTALL}" -eq 1 ]]; then
        uninstall
        exit 0
    fi
    if [[ "${DO_STOP}" -eq 1 ]]; then
        stop_agent
        exit 0
    fi
    if [[ "${DO_START}" -eq 1 ]]; then
        start_agent
        exit 0
    fi

    preflight
    install_vllm_metal
    fetch_agent
    install_shim
    render_artifacts
    if [[ "${NO_START}" -eq 0 ]]; then
        start_agent
    else
        log "--no-start set; LaunchAgent rendered at ${PLIST_DST} but not loaded."
    fi

    log "Done. Agent: ${BIN_DIR}/xerotier-xim-agent | venv: ${VENV} | logs: ${LOG_DIR}/"
}

main "$@"
