#!/usr/bin/env bash
# Раскладка серверной части Fern на VPS.
#
#   PB_SUPERUSER_PASSWORD=… ./server/deploy.sh              # выложить и проверить
#   ./server/deploy.sh --no-tests                           # только выложить
#
# Сервер общий с Togetherly, поэтому:
#   • боевой lava.pb.js копируется с датированным бэкапом;
#   • здоровье PocketBase проверяется до и после, и при отказе скрипт выходит
#     с ненулевым кодом: молчаливая выкладка на живой сервер хуже отменённой;
#   • отдельным шагом проверяется, что касса Togetherly отвечает как прежде.
set -euo pipefail

HOST="${FERN_VPS:-root@77.91.95.34}"
KEY="${FERN_VPS_KEY:-$HOME/.ssh/togetherly_vps}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_TESTS=1
[ "${1:-}" = "--no-tests" ] && RUN_TESTS=0

run_ssh() { ssh -o ConnectTimeout=25 -i "$KEY" "$HOST" "$@"; }
run_scp() { scp -q -o ConnectTimeout=25 -i "$KEY" "$@"; }

echo "→ проверяю сервер"
run_ssh 'curl -sf -m 5 -o /dev/null http://127.0.0.1:8090/api/health' \
  || { echo "PocketBase не отвечает ДО выкладки — ничего не трогаю"; exit 1; }

echo "→ служба талонов"
run_scp "$ROOT/fern_ticket.py" "$HOST:/tmp/fern_ticket.py"
run_scp "$ROOT/fern-ticket.service" "$HOST:/tmp/fern-ticket.service"
run_ssh 'install -m 644 /tmp/fern_ticket.py /opt/fern_ticket.py
         install -m 644 /tmp/fern-ticket.service /etc/systemd/system/fern-ticket.service
         systemctl daemon-reload
         systemctl restart fern-ticket
         sleep 1
         curl -sf -m 5 -o /dev/null http://127.0.0.1:8160/health'

echo "→ хуки PocketBase"
run_scp "$ROOT/pb_hooks/fern.pb.js" "$HOST:/tmp/fern.pb.js"
run_scp "$ROOT/pb_hooks/lava.pb.js" "$HOST:/tmp/lava.pb.js"
run_ssh 'STAMP=$(date +%Y%m%d-%H%M)
         cp -a /opt/pocketbase/pb_hooks/lava.pb.js "/opt/pocketbase/pb_hooks/lava.pb.js.bak-$STAMP"
         install -m 644 /tmp/fern.pb.js /opt/pocketbase/pb_hooks/fern.pb.js
         install -m 644 /tmp/lava.pb.js /opt/pocketbase/pb_hooks/lava.pb.js'

echo "→ скрипты и тесты"
run_ssh 'mkdir -p /opt/fern'
run_scp "$ROOT/setup_collections.py" "$ROOT/test_fern_routes.py" \
        "$ROOT/test_lava_fern.py" "$ROOT/test_fern_sync.py" "$HOST:/opt/fern/"

echo "→ жду перезапуск хуков"
sleep 8
run_ssh 'curl -sf -m 5 -o /dev/null http://127.0.0.1:8090/api/health' \
  || { echo "PocketBase не поднялся — смотреть journalctl -u pocketbase"; exit 1; }

echo "→ касса Togetherly"
run_ssh 'set -e
  export $(grep -h LAVA_WEBHOOK_KEY /etc/systemd/system/pocketbase.service.d/lava.conf | sed "s/Environment=//")
  answer=$(curl -s -m 15 -X POST http://127.0.0.1:8090/api/lava/webhook \
    -H "Content-Type: application/json" -H "X-Api-Key: $LAVA_WEBHOOK_KEY" \
    -d "{\"eventType\":\"payment.success\",\"status\":\"completed\",\"buyer\":{\"email\":\"deploy-probe@example.com\"},\"contractId\":\"deploy-probe\",\"product\":{\"id\":\"ec861b44-a4b7-49e3-aa0e-e4608abdb0f0\"},\"amount\":900,\"currency\":\"RUB\"}")
  echo "  Togetherly+ отвечает: $answer"
  case "$answer" in *"\"ok\":true"*) ;; *) echo "касса Togetherly ответила не так"; exit 1;; esac'

if [ "$RUN_TESTS" = "1" ]; then
  : "${PB_SUPERUSER_PASSWORD:?нужен PB_SUPERUSER_PASSWORD}"
  SU_EMAIL="${PB_SUPERUSER_EMAIL:-badzoff@gmail.com}"
  echo "→ тесты на сервере"
  run_ssh "cd /opt/fern
    export \$(grep -h LAVA_WEBHOOK_KEY /etc/systemd/system/pocketbase.service.d/lava.conf | sed 's/Environment=//')
    export PB_SUPERUSER_EMAIL='$SU_EMAIL'
    export PB_SUPERUSER_PASSWORD='$PB_SUPERUSER_PASSWORD'
    python3 test_fern_routes.py | tail -1
    python3 test_lava_fern.py | tail -1
    python3 test_fern_sync.py | tail -1"
fi

echo "готово"
