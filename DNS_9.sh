#!/usr/bin/env bash
# DNS Table Status Reporter

RED="\033[1;31m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
NC="\033[0m"

DOMAIN=$1
if [ -z "$DOMAIN" ]; then
  echo -e "${RED}Usage:${NC} $0 <domain>"
  exit 1
fi

# Helper for status
status_ok() { echo -e "${GREEN}[OK] Installed${NC}"; }
status_issue() { echo -e "${YELLOW}[!] Possible issue${NC}"; }
status_missing() { echo -e "${RED}[X] Missing${NC}"; }

# Helper to get TXT record for SPF/DMARC
get_txt() { dig +short TXT "$1" 2>/dev/null | sed -E 's/^"//;s/"$//' | paste -sd " | " -; }

# --- Registrar ---
REG=$(whois "$DOMAIN" 2>/dev/null | grep -i -m1 'Registrar:' | cut -d: -f2- | xargs)
[ -z "$REG" ] && REG="[X] Not found"

# --- Nameservers ---
NS_LIST=$(dig +short NS "$DOMAIN" | sed 's/\.$//')
if [ -z "$NS_LIST" ]; then
  NS_OUTPUT="${CYAN}[X] Missing${NC}"
else
  NS_OUTPUT=""
  count=0
  while read ns; do
    if [ $count -eq 0 ]; then
      NS_OUTPUT="${CYAN}$ns${NC}"
    else
      NS_OUTPUT="${NS_OUTPUT}\n$(printf '%-16s' '')| ${CYAN}$ns${NC}"
    fi
    count=$((count+1))
  done <<< "$NS_LIST"
fi

# Print header
echo
printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
echo -e "${CYAN}DNS Status Report for: $DOMAIN${NC}"
printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
echo -e "Registrar       : ${CYAN}$REG${NC}"
echo -e "Nameservers     | $NS_OUTPUT"
printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
printf "%-16s | %-50s\n" "Record" "Value / Status"
printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"

# --- A record ---
A_LIST=$(dig +short A "$DOMAIN" | paste -sd ", " -)
#printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
[ -n "$A_LIST" ] && printf "%-16s | %-50s\n" "A" "$A_LIST" || printf "%-16s | %-50s\n" "A" "$(status_missing)"

# --- AAAA record ---
AAAA_LIST=$(dig +short AAAA "$DOMAIN" | paste -sd ", " -)
printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
[ -n "$AAAA_LIST" ] && printf "%-16s | %-50s\n" "AAAA" "$AAAA_LIST" || printf "%-16s | %-50s\n" "AAAA" "$(status_missing)"

# --- MX ---
MX_LIST=$(dig +short MX "$DOMAIN" | sort -n)
printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
if [ -n "$MX_LIST" ]; then
  first=true
  while read mx; do
    if $first; then
      printf "%-16s | %-50s\n" "MX" "$mx"
      first=false
    else
      printf "%-16s | %-50s\n" "" "$mx"
    fi
  done <<< "$MX_LIST"
else
  printf "%-16s | %-50s\n" "MX" "$(status_missing)"
fi

# --- SPF ---
printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
SPF=$(get_txt "$DOMAIN" | grep -i 'v=spf1')
if [ -z "$SPF" ]; then
  printf "%-16s | %-50s\n" "SPF" "$(status_missing)"
elif echo "$SPF" | grep -qi 'all'; then
  printf "%-16s | %-50s\n" "SPF" "$(status_ok)"
else
  printf "%-16s | %-50s\n" "SPF" "$(status_issue)"
fi

# --- DMARC ---
printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
DMARC=$(get_txt "_dmarc.$DOMAIN")
if [ -z "$DMARC" ]; then
  printf "%-16s | %-50s\n" "DMARC" "$(status_missing)"
elif echo "$DMARC" | grep -qi 'v=dmarc1'; then
  printf "%-16s | %-50s\n" "DMARC" "$(status_ok)"
else
  printf "%-16s | %-50s\n" "DMARC" "$(status_issue)"
fi

# --- DKIM ---
printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
found_dkim=false
dkim_issue=false
for sel in default s1 s2 google selector1 selector2 mail smtp; do
  DKIM_REC=$(dig +short TXT "${sel}._domainkey.$DOMAIN")
  if [ -n "$DKIM_REC" ]; then
    found_dkim=true
    if ! echo "$DKIM_REC" | grep -qi 'v=DKIM1'; then
      dkim_issue=true
    fi
    break
  fi
done
if [ "$found_dkim" = true ]; then
  if [ "$dkim_issue" = true ]; then
    printf "%-16s | %-50s\n" "DKIM" "$(status_issue)"
  else
    printf "%-16s | %-50s\n" "DKIM" "$(status_ok)"
  fi
else
  printf "%-16s | %-50s\n" "DKIM" "$(status_missing)"
fi

# --- SOA ---
printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
dig +short SOA "$DOMAIN" >/dev/null 2>&1 && printf "%-16s | %-50s\n" "SOA" "$(status_ok)" || printf "%-16s | %-50s\n" "SOA" "$(status_missing)"

# --- PTR ---
printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
IP=$(dig +short A "$DOMAIN" | head -1)
if [ -n "$IP" ]; then
  PTR=$(dig +short -x "$IP" | paste -sd ", " -)
  [ -n "$PTR" ] && printf "%-16s | %-50s\n" "PTR" "$IP → $PTR" || printf "%-16s | %-50s\n" "PTR" "$IP → $(status_missing)"
else
  printf "%-16s | %-50s\n" "PTR" "$(status_missing)"
fi

printf "%-16s-+-%-50s\n" "----------------" "--------------------------------------------------"
echo -e "${CYAN}Check complete for $DOMAIN${NC}"
echo "Date DNS Check: $(date '+%Y-%m-%d %H:%M:%S')"
echo
echo
# ...existing code...