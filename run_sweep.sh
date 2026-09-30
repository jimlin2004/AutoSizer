#!/bin/bash
# === NOT PART OF UPSTREAM (yuxi120407/AutoSizer) ===
# Added by us (jimlin2004 fork, branch slm-clean-base) for running the local-SLM baseline.
# Upstream has no equivalent; nothing else in the repo depends on this file.
# ====================================================
# Run every circuit in AMS-SizingBench with one model, split into N parallel processes.
# Paper setting: 3 trials/circuit (main.py). For local Ollama models use the "-paper"
# variants (see ollama/create_paper_models.sh), e.g. qwen3:32b-paper.
#
# Usage (activate your conda env first): bash run_sweep.sh <model> [n_parts=2] [out_dir]
#   bash run_sweep.sh qwen3:32b-paper
#   bash run_sweep.sh qwen2.5:32b-paper 3
#   bash run_sweep.sh qwen3:32b-paper 2 ./results/baseline/qwen3-32b-paper
#
# Output: <out_dir>/part<i>/ (results + run.log together; one dir per part, so the summary
# JSONs don't race). out_dir defaults to ./results/<model with ':' -> '-'>.
# Re-running the same command resumes: circuits already SUCCESS in a part's summary JSON
# are skipped, so keep n_parts AND out_dir the same when resuming.
# Circuits are split by paper difficulty (Easy=1, Med=2, Hard=3) to balance the load.
set -e
cd "$(dirname "$0")"

MODEL=$1
NPARTS=${2:-2}
[ -z "$MODEL" ] && { echo "usage: bash run_sweep.sh <model> [n_parts=2] [out_dir]"; exit 1; }
# Uses whatever `python` is active: activate your conda env first (needs ngspice + openai).
command -v ngspice >/dev/null || { echo "ngspice not found on PATH - activate your conda env first"; exit 1; }
python -c "import openai" 2>/dev/null || { echo "python cannot import openai - activate your conda env first"; exit 1; }
[[ $MODEL == qwen* && $MODEL != *-paper ]] && echo "WARNING: '$MODEL' has no -paper suffix, so the paper sampling (top_p/top_k) is NOT applied"

OUT=${3:-./results/${MODEL//:/-}}
BENCH=AMS-SizingBench

weight() {
    case $1 in
        inverter|buffer|nand_gate|resistive_load_amp|diode_load_amp) echo 1 ;;
        3_stage_ring_osc|five_trans_ota|voltage_controlled_osc|telescopic_ota|current_mirror_ota|folded_cascode_ota) echo 2 ;;
        *) echo 3 ;;
    esac
}

# Greedy load balancing: heaviest circuits first, each to the currently lightest part.
declare -a load circuits
for ((p=0; p<NPARTS; p++)); do load[$p]=0; circuits[$p]=""; done
for c in $(for f in $BENCH/*.yaml; do n=$(basename $f .yaml); echo "$(weight $n) $n"; done | sort -rn -s | awk '{print $2}'); do
    best=0
    for ((p=1; p<NPARTS; p++)); do [ ${load[$p]} -lt ${load[$best]} ] && best=$p; done
    load[$best]=$(( ${load[$best]} + $(weight $c) ))
    circuits[$best]="${circuits[$best]} $BENCH/$c.yaml"
done

for ((p=0; p<NPARTS; p++)); do
    dir=$OUT/part$((p+1))
    mkdir -p "$dir"
    nohup python -u main.py --model "$MODEL" --output-dir "$dir" --circuits ${circuits[$p]} > "$dir/run.log" 2>&1 &
    echo "part$((p+1)) (load ${load[$p]}, pid $!): ${circuits[$p]//$BENCH\//}" | sed 's/\.yaml//g'
done
echo "logs: $OUT/part*/run.log"
