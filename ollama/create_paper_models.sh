#!/bin/bash
# === NOT PART OF UPSTREAM (yuxi120407/AutoSizer) ===
# Added by us (jimlin2004 fork, branch slm-clean-base) for running the local-SLM baseline.
# Upstream has no equivalent; nothing else in the repo depends on this file.
# ====================================================
# Create "-paper" variants of the pulled Ollama models with the paper's sampling
# setting (AutoSizer Sec. 4.1: temperature 0.4, top-p 0.85, top-k 20).
# Ollama's OpenAI-compatible /v1 endpoint ignores top_k sent in a request, so the
# values are set as server-side model defaults via a Modelfile instead
# (temperature is also sent per-request by the code; max_tokens=8192 is set in code).
#
# Usage: bash ollama/create_paper_models.sh [base_model ...]
#   e.g. bash ollama/create_paper_models.sh qwen3:32b
# Then run main.py with --model <base_model>-paper  (e.g. qwen3:32b-paper)
OLLAMA=${OLLAMA:-/mnt/HDD4/JimLin/tools/ollama/bin/ollama}
MODELS=("$@")
[ ${#MODELS[@]} -eq 0 ] && MODELS=(qwen2.5:14b-instruct qwen3.5:9b qwen3:4b-thinking qwen3.8:27b qwen2.5:32b qwen3:32b)

for base in "${MODELS[@]}"; do
    mf=$(mktemp)
    printf 'FROM %s\nPARAMETER temperature 0.4\nPARAMETER top_p 0.85\nPARAMETER top_k 20\n' "$base" > "$mf"
    "$OLLAMA" create "${base}-paper" -f "$mf" && echo "created ${base}-paper"
    rm -f "$mf"
done
