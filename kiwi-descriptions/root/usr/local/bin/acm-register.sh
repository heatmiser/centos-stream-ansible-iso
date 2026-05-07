#!/usr/bin/env bash
# ACM controller discovery via DNS SRV and node registration.
# Runs as a oneshot systemd service at boot after network is online.
# Queries _acm-listener._tcp.<ACM_DNS_DOMAIN> for the registration listener,
# collects hardware facts, and POSTs them to the FastAPI listener.
set -euo pipefail

CONF=/etc/acm-register.conf
if [ ! -f "${CONF}" ]; then
	echo "ACM: ${CONF} not found; skipping registration"
	exit 0
fi
# shellcheck source=/dev/null
source "${CONF}"

if [ "${ACM_REGISTRATION_ENABLED:-true}" != "true" ]; then
	echo "ACM: registration disabled via ACM_REGISTRATION_ENABLED; skipping"
	exit 0
fi

if [ -z "${ACM_DNS_DOMAIN:-}" ]; then
	echo "ACM: ACM_DNS_DOMAIN not set; skipping registration"
	exit 0
fi

SERVICE="${ACM_LISTENER_SERVICE:-_acm-listener._tcp}"
SRV_QUERY="${SERVICE}.${ACM_DNS_DOMAIN}"

# --- Discover controller via DNS SRV ---
echo "ACM: querying SRV record ${SRV_QUERY}"
SRV=$(dig +short SRV "${SRV_QUERY}" 2>/dev/null | head -1 || true)

if [ -z "${SRV}" ]; then
	echo "ACM: no SRV record found for ${SRV_QUERY}; skipping registration"
	exit 0
fi

CONTROLLER_PORT=$(echo "${SRV}" | awk '{print $3}')
SRV_TARGET=$(echo "${SRV}" | awk '{print $4}' | sed 's/\.$//')
CONTROLLER_IP=$(dig +short A "${SRV_TARGET}" 2>/dev/null | head -1 || true)

if [ -z "${CONTROLLER_IP}" ]; then
	echo "ACM: could not resolve SRV target ${SRV_TARGET}; skipping registration"
	exit 0
fi

echo "ACM: controller discovered at ${CONTROLLER_IP}:${CONTROLLER_PORT}"

# --- Collect hardware facts ---
SERIAL=$(dmidecode -t1 2>/dev/null \
	| grep -i 'serial number' | awk '{print $NF}' || echo "unknown")

IFACE=$(ip route show default 2>/dev/null \
	| awk '/default/ {print $5; exit}' || echo "")

if [ -z "${IFACE}" ]; then
	echo "ACM: no default route interface found; skipping registration"
	exit 1
fi

MAC=$(cat "/sys/class/net/${IFACE}/address" 2>/dev/null || echo "unknown")
IPV4=$(ip -4 addr show "${IFACE}" 2>/dev/null \
	| awk '/inet / {print $2}' | cut -d/ -f1 | head -1)

echo "ACM: serial=${SERIAL} interface=${IFACE} mac=${MAC} ip=${IPV4}"

PAYLOAD=$(printf '{"serial":"%s","ip":"%s","mac":"%s","interface":"%s"}' \
	"${SERIAL}" "${IPV4}" "${MAC}" "${IFACE}")

# --- POST with exponential backoff retry ---
DELAY=5
for attempt in 1 2 3 4 5; do
	HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
		-X POST "http://${CONTROLLER_IP}:${CONTROLLER_PORT}/register" \
		-H "Content-Type: application/json" \
		-d "${PAYLOAD}" \
		--max-time 10 || echo "000")

	if [ "${HTTP_CODE}" = "200" ]; then
		echo "ACM: registration successful (attempt ${attempt})"
		exit 0
	fi

	echo "ACM: attempt ${attempt} failed (HTTP ${HTTP_CODE}); retrying in ${DELAY}s"
	sleep "${DELAY}"
	DELAY=$((DELAY * 2))
done

echo "ACM: all registration attempts failed"
exit 1
