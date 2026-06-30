#!/bin/bash
# 로컬 VLM(이미지 맥락 해석) 활성화 스크립트.
#   - Ollama 서버 기동 확인
#   - 비전 모델 받기 (기본 llava:7b)
#   - config.json 의 vlmEnabled 를 true 로 전환
#
# 사용법:
#   ./setup_vlm.sh            # llava:7b 사용
#   ./setup_vlm.sh moondream  # 더 가벼운 모델
set -euo pipefail

MODEL="${1:-llava:7b}"
CONFIG="$HOME/Library/Application Support/SmartCapture/config.json"

if ! command -v ollama >/dev/null 2>&1; then
    echo "❌ ollama 가 없습니다. https://ollama.com 에서 설치하세요."
    exit 1
fi

# 서버가 떠 있지 않으면 백그라운드로 기동
if ! curl -s --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "▶︎ Ollama 서버 기동..."
    (ollama serve >/tmp/ollama.log 2>&1 &)
    for _ in $(seq 1 15); do
        curl -s --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1 && break
        sleep 1
    done
fi

echo "▶︎ 비전 모델 받기: ${MODEL} (수 GB, 시간이 걸릴 수 있습니다)"
ollama pull "${MODEL}"

echo "▶︎ config.json 의 vlmEnabled=true, vlmModel=${MODEL} 설정..."
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
print("   저장:", path)
PY

echo ""
echo "✅ 완료. SmartCapture 을 재실행하면 캡처마다 맥락 캡션이 생성됩니다."
echo "   재실행:  pkill -f SmartCapture; open SmartCapture.app"
echo "   ※ Ollama 서버는 로그인 시 자동 기동되도록 'ollama serve' 를 켜두는 게 좋습니다."