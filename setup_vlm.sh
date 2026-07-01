#!/bin/bash
# Enable local VLM image-context captions.
#   - Ensure the Ollama server is running
#   - Pull a vision model (default: llava:7b)
#   - Set vlmEnabled to true in config.json
#
# Usage:
#   ./setup_vlm.sh            # use llava:7b
#   ./setup_vlm.sh moondream  # a lighter model
set -euo pipefail

MODEL="${1:-llava:7b}"
CONFIG="$HOME/Library/Application Support/SmartCapture/config.json"

if ! command -v ollama >/dev/null 2>&1; then
    echo "Ollama is not installed. Get it from https://ollama.com"
    exit 1
fi

# Start the server in the background if it is not already running.
if ! curl -s --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "Starting Ollama server..."
    (ollama serve >/tmp/ollama.log 2>&1 &)
    for _ in $(seq 1 15); do
        curl -s --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1 && break
        sleep 1
    done
fi

echo "Pulling vision model: ${MODEL} (several GB, may take a while)"
ollama pull "${MODEL}"

echo "Setting vlmEnabled=true and vlmModel=${MODEL} in config.json"
python3 - "$CONFIG" "$MODEL" <<'PY'
import json, sys, os
path, model = sys.argv[1], sys.argv[2]
cfg = {}
if os.path.exists(path):
    with open(path) as f:
        cfg = json.load(f)
cfg["vlmEnabled"] = True
cfg["vlmModel"] = model
cfg.setdefault("vlmEndpoint", "http://localhost:11434")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False, sort_keys=True)
print("Saved:", path)
PY

echo ""
echo "Done. Relaunch SmartCapture to generate captions for new captures:"
echo "  pkill -f SmartCapture; open SmartCapture.app"
echo "Tip: keep 'ollama serve' running (e.g. at login) so captions work automatically."
