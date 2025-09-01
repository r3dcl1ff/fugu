#!/usr/bin/env bash
set -euo pipefail

#needs Project Discovery's API key , community version in order to run ASNmap, specify with -k flag

usage(){ cat <<'EOF'
Usage: country_assets.sh [-k PDCP_API_KEY]
Requires: curl jq asnmap mapcidr
EOF
}

API_KEY="${PDCP_API_KEY:-}"
while getopts ":k:h" opt; do
  case "$opt" in
    k) API_KEY="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 2 ;;
  esac
done
shift $((OPTIND-1))

for cmd in curl jq asnmap mapcidr; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing dependency: $cmd" >&2; exit 1; }
done

if [[ -z "$API_KEY" ]]; then read -s -p "Enter PDCP API key : " API_KEY; echo; fi
[[ -z "$API_KEY" ]] && { echo "PDCP API key is required." >&2; exit 1; }
export PDCP_API_KEY="$API_KEY"

read -rp "Enter two-letter country code (e.g., CH): " CC_IN
CC_UPPER="$(printf "%s" "$CC_IN" | tr '[:lower:]' '[:upper:]')"
case "$CC_UPPER" in UK) CC_UPPER=GB ;; EL) CC_UPPER=GR ;; esac
CC_LOWER="$(printf "%s" "$CC_UPPER" | tr '[:upper:]' '[:lower:]')"
[[ "$CC_UPPER" =~ ^[A-Z]{2}$ ]] || { echo "Invalid country code." >&2; exit 1; }

OUTDIR="out_${CC_UPPER}"; mkdir -p "$OUTDIR"
ASNS_FILE="${OUTDIR}/asn.txt"
CIDRS_FILE="${OUTDIR}/cidrs.txt"
IP_FILE="${OUTDIR}/ip.txt"
TMP_ASN_JSON="${OUTDIR}/_ripe_asns.json"
TMP_ASNMAP_CIDRS="${OUTDIR}/_asnmap.cidrs"
TMP_IPDENY_CIDRS="${OUTDIR}/_ipdeny.cidrs"
TMP_ALL_CIDRS="${OUTDIR}/_all.cidrs"
TMP_IPS_ASN="${OUTDIR}/_ips_from_asn.txt"
TMP_IPS_IPDENY="${OUTDIR}/_ips_from_ipdeny.txt"

echo "[1/5] Fetching ASNs for ${CC_UPPER}…"
curl -fsSL "https://stat.ripe.net/data/country-asns/data.json?resource=${CC_UPPER}&lod=1" -o "$TMP_ASN_JSON" || true
if jq -er '.data.asns.routed // [] | length > 0' "$TMP_ASN_JSON" >/dev/null 2>&1; then
  jq -r '.data.asns.routed // [] | .[]' "$TMP_ASN_JSON" | awk '{print "AS"$1}' | sort -u > "$ASNS_FILE"
else
  curl -fsSL "https://stat.ripe.net/data/country-resource-list/data.json?resource=${CC_UPPER}" \
  | jq -r '.data.resources.asn // [] | .[]' | awk '{print "AS"$1}' | sort -u > "$ASNS_FILE"
fi
[[ -s "$ASNS_FILE" ]] || { echo "No ASNs found for ${CC_UPPER}." >&2; exit 1; }
echo "  → ASNs: $(wc -l < "$ASNS_FILE") -> $ASNS_FILE"

echo "[2/5] Downloading IPDeny IPv4 CIDRs…"

if ! curl -fsSL "https://www.ipdeny.com/ipblocks/data/countries/${CC_LOWER}.zone" -o "$TMP_IPDENY_CIDRS"; then
  curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${CC_LOWER}.zone" -o "$TMP_IPDENY_CIDRS"
fi
awk -F/ 'NF==2 && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $2 ~ /^[0-9]+$/' "$TMP_IPDENY_CIDRS" \
  | sort -u > "${TMP_IPDENY_CIDRS}.tmp" && mv "${TMP_IPDENY_CIDRS}.tmp" "$TMP_IPDENY_CIDRS"
echo "  → IPDeny CIDRs: $(wc -l < "$TMP_IPDENY_CIDRS")"

echo "[3/5] Running ASNMap (per-ASN; skipping no-results)…"
: > "$TMP_ASNMAP_CIDRS"
while IFS= read -r ASN; do
  asnmap -a "$ASN" -silent >>"$TMP_ASNMAP_CIDRS" 2>/dev/null || true
  sleep 0.05
done < "$ASNS_FILE"
awk -F/ 'NF==2 && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $2 ~ /^[0-9]+$/' "$TMP_ASNMAP_CIDRS" \
  | sort -u > "${TMP_ASNMAP_CIDRS}.tmp" && mv "${TMP_ASNMAP_CIDRS}.tmp" "$TMP_ASNMAP_CIDRS"
echo "  → ASNMap CIDRs: $(wc -l < "$TMP_ASNMAP_CIDRS")"

echo "[4/5] Aggregating CIDRs…"
cat "$TMP_ASNMAP_CIDRS" "$TMP_IPDENY_CIDRS" | sort -u > "$TMP_ALL_CIDRS"
if [[ -s "$TMP_ALL_CIDRS" ]]; then
  mapcidr -aggregate -silent < "$TMP_ALL_CIDRS" > "$CIDRS_FILE" || true
else
  : > "$CIDRS_FILE"
fi
echo "  → Final CIDRs: $(wc -l < "$CIDRS_FILE") -> $CIDRS_FILE"

echo "[5/5] Expanding to IPv4s (files only)…"
: > "$TMP_IPS_ASN"; : > "$TMP_IPS_IPDENY"
[[ -s "$TMP_ASNMAP_CIDRS"  ]] && mapcidr -silent < "$TMP_ASNMAP_CIDRS"  > "$TMP_IPS_ASN"    || true
[[ -s "$TMP_IPDENY_CIDRS" ]] && mapcidr -silent < "$TMP_IPDENY_CIDRS" > "$TMP_IPS_IPDENY" || true
cat "$TMP_IPS_ASN" "$TMP_IPS_IPDENY" \
  | awk -F. 'NF==4' \
  | sort -t . -k1,1n -k2,2n -k3,3n -k4,4n \
  | uniq > "$IP_FILE"
echo "  → Final IPv4s: $(wc -l < "$IP_FILE") -> $IP_FILE"

echo
echo "Done for ${CC_UPPER}."
echo "Outputs:"
echo "  - $ASNS_FILE"
echo "  - $CIDRS_FILE"
echo "  - $IP_FILE"
