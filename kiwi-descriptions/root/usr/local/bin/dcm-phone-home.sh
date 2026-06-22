#!/usr/bin/env bash
# dcm-phone-home: Generic automation job executor.
# Discovers the controller via explicit config or DNS SRV record, polls for
# jobs, executes them, and reports results back. Exits silently if no
# controller is reachable. Loops until the system is powered off or rebooted.
set -euo pipefail

CONF=/etc/dcm-phone-home.conf
JOB_FILE=/tmp/dcm-job.json
RESULT_FILE=/tmp/dcm-result.json
SCRIPT_FILE=/tmp/dcm-job-script.sh

# --- Load config ---
# Supported vars:
#   DCM_CONTROLLER_URL      — explicit controller URL; skips DNS SRV lookup
#   DCM_DNS_DOMAIN          — domain for SRV lookup (_dcm-automation._tcp.<domain>)
#   DCM_REGISTRATION_ENABLED — set to "false" to disable entirely (default: true)
#   DCM_POLL_INTERVAL       — seconds between job polls when idle (default: 30)
if [ ! -f "${CONF}" ]; then
    echo "DCM: ${CONF} not found; exiting"
    exit 0
fi
# shellcheck source=/dev/null
source "${CONF}"

if [ "${DCM_REGISTRATION_ENABLED:-true}" != "true" ]; then
    echo "DCM: registration disabled via DCM_REGISTRATION_ENABLED; exiting"
    exit 0
fi

DCM_POLL_INTERVAL="${DCM_POLL_INTERVAL:-30}"

# --- Discover controller URL ---
CONTROLLER_URL="${DCM_CONTROLLER_URL:-}"

if [ -z "${CONTROLLER_URL}" ]; then
    if [ -z "${DCM_DNS_DOMAIN:-}" ]; then
        echo "DCM: neither DCM_CONTROLLER_URL nor DCM_DNS_DOMAIN configured; exiting"
        exit 0
    fi

    SRV_QUERY="_dcm-automation._tcp.${DCM_DNS_DOMAIN}"
    echo "DCM: querying SRV ${SRV_QUERY}"
    SRV=$(dig +short SRV "${SRV_QUERY}" 2>/dev/null | head -1 || true)

    if [ -z "${SRV}" ]; then
        echo "DCM: no SRV record found for ${SRV_QUERY}; exiting"
        exit 0
    fi

    SRV_PORT=$(echo "${SRV}" | awk '{print $3}')
    SRV_TARGET=$(echo "${SRV}" | awk '{print $4}' | sed 's/\.$//')
    SRV_HOST=$(dig +short A "${SRV_TARGET}" 2>/dev/null | head -1 || true)

    if [ -z "${SRV_HOST}" ]; then
        echo "DCM: could not resolve SRV target ${SRV_TARGET}; exiting"
        exit 0
    fi

    CONTROLLER_URL="http://${SRV_HOST}:${SRV_PORT}"
fi

echo "DCM: controller at ${CONTROLLER_URL}"

# --- Node identity ---
SERIAL=$(dmidecode -t1 2>/dev/null \
    | awk -F': ' '/Serial Number/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' \
    || echo "unknown")

DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}' || echo "")
if [ -z "${DEFAULT_IFACE}" ]; then
    echo "DCM: no default route interface; exiting"
    exit 1
fi

MAC=$(cat "/sys/class/net/${DEFAULT_IFACE}/address" 2>/dev/null || echo "unknown")
IPV4=$(ip -4 addr show "${DEFAULT_IFACE}" 2>/dev/null \
    | awk '/inet / {print $2}' | cut -d/ -f1 | head -1 || echo "")

echo "DCM: identity serial=${SERIAL} mac=${MAC} ip=${IPV4}"

# --- Helpers ---
_json_field() {
    python3 -c "
import json, sys
try:
    d = json.load(open('${JOB_FILE}'))
    print(d.get('${1}') or '')
except Exception:
    print('')
" 2>/dev/null || echo ""
}

_post_result() {
    local report_to="${1}"
    local job_id="${2}"
    local status="${3}"

    local result_json
    result_json=$(python3 - "${job_id}" "${status}" <<'PYEOF'
import json, sys
job_id, status = sys.argv[1], sys.argv[2]
try:
    with open('/tmp/dcm-result.json') as f:
        content = f.read().strip()
    try:
        result = json.loads(content)
    except json.JSONDecodeError:
        result = {"output": content}
except OSError:
    result = {}
print(json.dumps({"job_id": job_id, "status": status, "result": result}))
PYEOF
)
    curl -s -o /dev/null \
        -X POST "${report_to}" \
        -H "Content-Type: application/json" \
        -d "${result_json}" \
        --max-time 15 || true
}

# --- Job execution loop ---
while true; do
    # Check in and request a job
    HTTP_CODE=$(curl -s -o "${JOB_FILE}" -w "%{http_code}" \
        -X POST "${CONTROLLER_URL}/api/automation/check-in" \
        -H "Content-Type: application/json" \
        -d "{\"serial\":\"${SERIAL}\",\"mac\":\"${MAC}\",\"ip\":\"${IPV4}\"}" \
        --max-time 15 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" != "200" ]; then
        echo "DCM: check-in failed (HTTP ${HTTP_CODE}); retrying in ${DCM_POLL_INTERVAL}s"
        sleep "${DCM_POLL_INTERVAL}"
        continue
    fi

    JOB_TYPE=$(_json_field "type")
    JOB_ID=$(_json_field "job_id")
    REPORT_TO=$(_json_field "report_to")

    if [ -z "${JOB_TYPE}" ] || [ "${JOB_TYPE}" = "None" ]; then
        echo "DCM: no job assigned; polling in ${DCM_POLL_INTERVAL}s"
        sleep "${DCM_POLL_INTERVAL}"
        continue
    fi

    echo "DCM: job_id=${JOB_ID} type=${JOB_TYPE}"

    EXIT_CODE=0
    case "${JOB_TYPE}" in
        discovery)
            echo "DCM: collecting hardware manifest"
            /usr/local/bin/dcm-collect-hardware.sh > "${RESULT_FILE}" 2>&1 \
                || EXIT_CODE=$?
            ;;
        script)
            PAYLOAD=$(python3 -c "
import json, base64
d = json.load(open('${JOB_FILE}'))
print(base64.b64decode(d.get('payload', '')).decode())
" 2>/dev/null || echo "")
            printf '%s\n' "${PAYLOAD}" > "${SCRIPT_FILE}"
            chmod 700 "${SCRIPT_FILE}"
            "${SCRIPT_FILE}" > "${RESULT_FILE}" 2>&1 || EXIT_CODE=$?
            rm -f "${SCRIPT_FILE}"
            ;;
        shell)
            PAYLOAD=$(python3 -c "
import json, base64
d = json.load(open('${JOB_FILE}'))
print(base64.b64decode(d.get('payload', '')).decode())
" 2>/dev/null || echo "")
            bash -c "${PAYLOAD}" > "${RESULT_FILE}" 2>&1 || EXIT_CODE=$?
            ;;
        *)
            echo "DCM: unknown job type '${JOB_TYPE}'; skipping" > "${RESULT_FILE}"
            EXIT_CODE=1
            ;;
    esac

    if [ -n "${REPORT_TO}" ]; then
        STATUS="success"
        [ "${EXIT_CODE}" -ne 0 ] && STATUS="error"
        _post_result "${REPORT_TO}" "${JOB_ID}" "${STATUS}"
        echo "DCM: result posted to ${REPORT_TO} (status=${STATUS} exit=${EXIT_CODE})"
    fi
done
