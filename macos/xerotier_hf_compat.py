# SPDX-License-Identifier: MIT
# Xerotier - HuggingFace Hub Compatibility Shim
#
# Installed as a site-packages module and loaded via .pth file at Python
# startup. This ensures the patch applies to ALL Python processes including
# subprocesses spawned by vLLM (e.g., model architecture inspection via
# `python3 -m vllm.model_executor.models.registry`).
#
# Problem: huggingface-hub major version can drift ahead of what transformers
# expects. The version check fires at import time inside transformers/__init__.py
# -> dependency_versions_check.py, causing an ImportError in any process that
# imports transformers (directly or transitively).
#
# Fix: Patch importlib.metadata.version() to report huggingface_hub as 1.99.0
# when the real version is >= 1.0. This satisfies the >=1.5.0,<2.0 constraint
# used by current transformers without downgrading the package. The patch is
# safe because Xerotier never accesses the HuggingFace Hub -- all models are
# served from local disk.

import importlib.metadata as _ilm

_real_version = _ilm.version


def _patched_version(name):
    """Return spoofed version for huggingface_hub when >= 2.0."""
    if name.replace("-", "_").lower() == "huggingface_hub":
        try:
            real = _real_version(name)
            parts = real.split(".")
            major = int(parts[0]) if parts else 0
            if major >= 2:
                return "1.99.0"
        except Exception:
            pass
    return _real_version(name)


_ilm.version = _patched_version
