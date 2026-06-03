#!/bin/bash
# SPDX-License-Identifier: MIT
# Xerotier Backend Agent Entrypoint (macOS / Apple Silicon)
# Handles one-time enrollment and subsequent runs under launchd.

set -e

ENROLLMENT_STATE_FILE="${HOME}/.config/xerotier/enrollment.json"

# Agent binary installed by xim-metalctl.sh (override with XEROTIER_AGENT_BIN).
AGENT_BIN="${XEROTIER_AGENT_BIN:-${HOME}/.local/bin/xerotier-xim-agent}"

# Apple Silicon has no CUDA/ROCm GPU to detect; MLX uses unified memory and
# tensor_parallel_size must stay 1. Disable the agent's GPU auto-configuration.
export XEROTIER_AGENT_AUTO_CONFIGURE_GPU=0

# Default the vLLM launcher to the macOS parity wrapper unless overridden.
export XEROTIER_AGENT_VLLM_PATH="${XEROTIER_AGENT_VLLM_PATH:-${HOME}/.local/bin/xerotier-vllm}"

# Build enrollment arguments
build_enroll_args() {
    local args=("enroll")

    if [[ -n "${XEROTIER_AGENT_JOIN_KEY}" ]]; then
        args+=("--join-key" "${XEROTIER_AGENT_JOIN_KEY}")
    fi

    if [[ -n "${XEROTIER_AGENT_MAX_CONCURRENT}" ]]; then
        args+=("--max-concurrent" "${XEROTIER_AGENT_MAX_CONCURRENT}")
    fi

    if [[ -n "${XEROTIER_AGENT_LOG_LEVEL}" ]]; then
        args+=("--log-level" "${XEROTIER_AGENT_LOG_LEVEL}")
    fi

    if [[ "${XEROTIER_AGENT_ALLOW_INSECURE}" == "1" ]] || [[ "${XEROTIER_AGENT_ALLOW_INSECURE}" == "true" ]]; then
        args+=("--insecure")
    fi

    echo "${args[@]}"
}

# Build run arguments
build_run_args() {
    local args=("run")

    if [[ -n "${XEROTIER_AGENT_LOG_LEVEL}" ]]; then
        args+=("--log-level" "${XEROTIER_AGENT_LOG_LEVEL}")
    fi

    if [[ -n "${XEROTIER_AGENT_MAX_CONCURRENT}" ]]; then
        args+=("--max-concurrent" "${XEROTIER_AGENT_MAX_CONCURRENT}")
    fi

    if [[ -n "${XEROTIER_AGENT_VLLM_PATH}" ]]; then
        args+=("--vllm-path" "${XEROTIER_AGENT_VLLM_PATH}")
    fi

    if [[ -n "${XEROTIER_AGENT_VLLM_SALT_SECRET}" ]]; then
        args+=("--vllm-salt-secret" "${XEROTIER_AGENT_VLLM_SALT_SECRET}")
    fi

    if [[ -n "${XEROTIER_AGENT_VLLM_SOCKET_PATH}" ]]; then
        args+=("--vllm-socket-path" "${XEROTIER_AGENT_VLLM_SOCKET_PATH}")
    fi

    if [[ -n "${XEROTIER_AGENT_METRICS_PORT}" ]]; then
        args+=("--metrics-port" "${XEROTIER_AGENT_METRICS_PORT}")
    fi

    if [[ "${XEROTIER_AGENT_DISABLE_METRICS_SERVER}" == "1" ]] || \
       [[ "${XEROTIER_AGENT_DISABLE_METRICS_SERVER}" == "true" ]]; then
        args+=("--disable-metrics-server")
    fi

    # Handle VLLM_ARGS (space-separated extra arguments)
    # Uses = syntax so values starting with -- are not parsed as flags
    if [[ -n "${XEROTIER_AGENT_VLLM_ARGS}" ]]; then
        for arg in ${XEROTIER_AGENT_VLLM_ARGS}; do
            args+=("--vllm-arg=${arg}")
        done
    fi

    # Handle VLLM_ENV (space-separated KEY=VALUE pairs)
    # Skips entries with empty values (e.g. KEY= when env var was unset)
    if [[ -n "${XEROTIER_AGENT_VLLM_ENV}" ]]; then
        for env in ${XEROTIER_AGENT_VLLM_ENV}; do
            local val="${env#*=}"
            if [[ -n "${val}" ]]; then
                args+=("--vllm-env=${env}")
            fi
        done
    fi

    echo "${args[@]}"
}

# Main entrypoint logic
main() {
    # Ensure config directory exists
    mkdir -p "$(dirname "${ENROLLMENT_STATE_FILE}")"

    # If arguments are passed directly, use them (allows manual override)
    if [[ $# -gt 0 ]]; then
        exec "${AGENT_BIN}" "$@"
    fi

    # Check if enrollment state exists
    if [[ -f "${ENROLLMENT_STATE_FILE}" ]]; then
        echo "[entrypoint] Enrollment state found at ${ENROLLMENT_STATE_FILE}"
        echo "[entrypoint] Starting agent..."

        run_args=$(build_run_args)
        echo "[entrypoint] Running: ${AGENT_BIN} ${run_args}"
        # shellcheck disable=SC2086
        exec "${AGENT_BIN}" ${run_args}
    fi

    # No enrollment state - need to enroll first
    if [[ -z "${XEROTIER_AGENT_JOIN_KEY}" ]]; then
        echo "[entrypoint] ERROR: No enrollment state found and XEROTIER_AGENT_JOIN_KEY not set."
        echo ""
        echo "  Either:"
        echo "    1. Set XEROTIER_AGENT_JOIN_KEY for first-time enrollment"
        echo "    2. Provide existing enrollment state at:"
        echo "       ${ENROLLMENT_STATE_FILE}"
        echo ""
        echo "  Get a join key from your Xerotier dashboard:"
        echo "    Dashboard -> Infrastructure -> Agents -> Generate Join Key"
        echo ""
        exit 1
    fi

    echo "[entrypoint] No enrollment state found. Enrolling with join key..."

    enroll_args=$(build_enroll_args)
    echo "[entrypoint] Running: ${AGENT_BIN} ${enroll_args}"

    # shellcheck disable=SC2086
    if ! "${AGENT_BIN}" ${enroll_args}; then
        echo "[entrypoint] ERROR: Enrollment failed."
        exit 1
    fi

    echo "[entrypoint] Enrollment successful. Starting agent..."

    run_args=$(build_run_args)
    echo "[entrypoint] Running: ${AGENT_BIN} ${run_args}"
    # shellcheck disable=SC2086
    exec "${AGENT_BIN}" ${run_args}
}

main "$@"
