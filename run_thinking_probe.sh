#!/bin/bash
# === NOT PART OF UPSTREAM (yuxi120407/AutoSizer) ===
# Added by us (jimlin2004 fork, branch slm-clean-base) for the "why does the thinking model survive the
# broken prompt example" analysis. Upstream has no equivalent; nothing else in the repo depends on this file.
# ====================================================
# Run a small, hand-picked set of circuits with --save-thinking, so that every LLM call (prompt, thinking
# text, reply) is saved to <trial dir>/thinking_log.jsonl (one file per trial, one JSON line per call).
#
# Usage (activate your conda env first): bash run_thinking_probe.sh <model> <base_url> [out_dir] [max_tokens=32768]
#   bash run_thinking_probe.sh qwen3-4b-thinking-vllm http://127.0.0.1:18001/v1
#   bash run_thinking_probe.sh qwen3-4b-instruct-vllm http://127.0.0.1:18000/v1
# <model> must equal the vLLM server's --served-model-name and start with "qwen", "ollama:" or "local:". Run it once per server
# (thinking and instruct) to get both sides of the comparison. Sampling is whatever the server was started with.
# out_dir defaults to ./results/thinking_probe/<model>; the circuits are split over 2 processes (part1, part2).
# Re-running the same command resumes: circuits already SUCCESS in a part's summary JSON are skipped.
#
# Why these circuits (4B instruct vs 4B thinking on vLLM, trials that met all specs, out of 3):
#   inverter               Easy   4 metrics  2 vars    1/3 vs 3/3   smallest; we already have one recorded sample
#   nand_gate              Easy   8 metrics  4 vars    0/3 vs 3/3   most metrics = longest impact field in the broken example
#   telescopic_ota         Medium 4 metrics  4 vars    0/3 vs 3/3
#   xor_gate               Hard   6 metrics  4 vars    0/3 vs 2/3   thinking sometimes fails
#   dfcfc                  Hard   4 metrics 10 vars    0/3 vs 3/3   many variables
#   folded_cascode_ota_lp  Hard   7 metrics 10 vars    0/3 vs 0/3   both fail: a counter-example for thinking
set -e
cd "$(dirname "$0")"

MODEL=$1
BASE_URL=$2
[ -z "$MODEL" ] || [ -z "$BASE_URL" ] && { echo "usage: bash run_thinking_probe.sh <model> <base_url> [out_dir] [max_tokens]"; exit 1; }
OUT=${3:-./results/thinking_probe/$MODEL}
MT=${4:-32768}
[[ $MT =~ ^[0-9]+$ ]] || { echo "max_tokens must be a positive integer, got '$MT'"; exit 1; }
export AUTOSIZER_MAX_TOKENS=$MT
export OLLAMA_BASE_URL=$BASE_URL

# Uses whatever `python` is active: activate your conda env first (needs ngspice + openai).
command -v ngspice >/dev/null || { echo "ngspice not found on PATH - activate your conda env first"; exit 1; }
python -c "import openai" 2>/dev/null || { echo "python cannot import openai - activate your conda env first"; exit 1; }
curl -s -m 10 "$BASE_URL/models" | grep -q "\"$MODEL\"" || { echo "server at $BASE_URL does not list model '$MODEL' (check the URL and --served-model-name)"; exit 1; }

BENCH=AMS-SizingBench
# Two parts of similar load (Easy=1, Medium=2, Hard=3): part1 = 3+3+1 = 7, part2 = 3+2+1 = 6
PART1="dfcfc folded_cascode_ota_lp nand_gate"
PART2="xor_gate telescopic_ota inverter"

i=0
for group in "$PART1" "$PART2"; do
    i=$((i+1))
    dir=$OUT/part$i
    mkdir -p "$dir"
    files=""
    for c in $group; do files="$files $BENCH/$c.yaml"; done
    nohup python -u main.py --model "$MODEL" --output-dir "$dir" --save-thinking --circuits $files > "$dir/run.log" 2>&1 &
    echo "part$i (pid $!): $group"
done
echo "model $MODEL @ $BASE_URL, max_tokens $MT, saving thinking"
echo "logs: $OUT/part*/run.log   records: $OUT/part*/<circuit>/test_trial_*/thinking_log.jsonl"
