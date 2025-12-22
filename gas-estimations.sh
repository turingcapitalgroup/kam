#!/bin/bash

# Gas Estimation Script
# Runs forge test --gas-report and creates a pretty table with USD cost estimates

# Force C locale for consistent number formatting (use . as decimal separator)
export LC_ALL=C

OUTPUT_FILE=".gas-estimations"
TEMP_FILE=$(mktemp)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Box drawing characters
TL='╭'  # Top left
TR='╮'  # Top right
BL='╰'  # Bottom left
BR='╯'  # Bottom right
H='─'   # Horizontal
V='│'   # Vertical
LT='├'  # Left T
RT='┤'  # Right T
TT='┬'  # Top T
BT='┴'  # Bottom T
CR='┼'  # Cross

echo -e "${CYAN}${BOLD}⛽ Running forge test --gas-report...${RESET}"
forge test --gas-report > "$TEMP_FILE" 2>&1 || true

# Fetch current mainnet gas price from Etherscan API
echo -e "${CYAN}📡 Fetching current mainnet gas price...${RESET}"
GAS_PRICE_GWEI=""

# Try with API key first
if [ -n "$ETHERSCAN_MAINNET_KEY" ]; then
    GAS_RESPONSE=$(curl -s "https://api.etherscan.io/api?module=gastracker&action=gasoracle&apikey=$ETHERSCAN_MAINNET_KEY" 2>/dev/null || echo "{}")
    if echo "$GAS_RESPONSE" | jq -e '.result.ProposeGasPrice' >/dev/null 2>&1; then
        GAS_PRICE_GWEI=$(echo "$GAS_RESPONSE" | jq -r '.result.ProposeGasPrice')
    fi
fi

# Fallback to public API if no API key or failed
if [ -z "$GAS_PRICE_GWEI" ] || [ "$GAS_PRICE_GWEI" = "null" ]; then
    GAS_RESPONSE=$(curl -s "https://api.etherscan.io/api?module=gastracker&action=gasoracle" 2>/dev/null || echo "{}")
    if echo "$GAS_RESPONSE" | jq -e '.result.ProposeGasPrice' >/dev/null 2>&1; then
        GAS_PRICE_GWEI=$(echo "$GAS_RESPONSE" | jq -r '.result.ProposeGasPrice')
    fi
fi

# Default fallback
if [ -z "$GAS_PRICE_GWEI" ] || [ "$GAS_PRICE_GWEI" = "null" ]; then
    GAS_PRICE_GWEI="0.048"
    echo -e "${YELLOW}⚠️  Could not fetch gas price, using default: ${GAS_PRICE_GWEI} gwei${RESET}"
fi

# Fetch current ETH price
echo -e "${CYAN}💰 Fetching current ETH price...${RESET}"
ETH_PRICE=""

ETH_RESPONSE=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd" 2>/dev/null || echo "{}")
if echo "$ETH_RESPONSE" | jq -e '.ethereum.usd' >/dev/null 2>&1; then
    ETH_PRICE=$(echo "$ETH_RESPONSE" | jq -r '.ethereum.usd')
fi

# Default fallback
if [ -z "$ETH_PRICE" ] || [ "$ETH_PRICE" = "null" ]; then
    ETH_PRICE="3500"
    echo -e "${YELLOW}⚠️  Could not fetch ETH price, using default: \$${ETH_PRICE}${RESET}"
fi

echo -e "${CYAN}📊 Parsing gas report and generating estimates...${RESET}"
echo ""

# Function to calculate USD cost
calc_usd() {
    local gas=$1
    echo "scale=6; $gas * $GAS_PRICE_GWEI * 0.000000001 * $ETH_PRICE" | bc
}

# Function to format USD
format_usd() {
    local cost=$1
    if [ -z "$cost" ] || [ "$cost" = "" ]; then
        echo "N/A"
        return
    fi
    if [ "$(echo "$cost < 0.01" | bc 2>/dev/null)" -eq 1 ] 2>/dev/null; then
        echo "< \$0.01"
    elif [ "$(echo "$cost < 1" | bc 2>/dev/null)" -eq 1 ] 2>/dev/null; then
        printf "\$%.4f" "$cost"
    else
        printf "\$%.2f" "$cost"
    fi
}

# Function to format number with commas
format_number() {
    echo "$1" | sed ':a;s/\B[0-9]\{3\}\>$/,&/;ta'
}

# Function to pad string to width
pad_right() {
    local str="$1"
    local width="$2"
    printf "%-${width}s" "$str"
}

pad_left() {
    local str="$1"
    local width="$2"
    printf "%${width}s" "$str"
}

# Function to repeat character
repeat_char() {
    local char="$1"
    local count="$2"
    printf "%0.s$char" $(seq 1 $count)
}

# Column widths
COL_FUNC=35
COL_MIN=12
COL_AVG=12
COL_MED=12
COL_MAX=12
COL_USD=14
TOTAL_WIDTH=$((COL_FUNC + COL_MIN + COL_AVG + COL_MED + COL_MAX + COL_USD + 7))

# Function to print table header
print_table_header() {
    echo -e "${BLUE}${TL}$(repeat_char $H $COL_FUNC)${TT}$(repeat_char $H $COL_MIN)${TT}$(repeat_char $H $COL_AVG)${TT}$(repeat_char $H $COL_MED)${TT}$(repeat_char $H $COL_MAX)${TT}$(repeat_char $H $COL_USD)${TR}${RESET}"
    echo -e "${BLUE}${V}${RESET}${BOLD}$(pad_right " Function" $COL_FUNC)${RESET}${BLUE}${V}${RESET}${BOLD}$(pad_left "Min " $COL_MIN)${RESET}${BLUE}${V}${RESET}${BOLD}$(pad_left "Avg " $COL_AVG)${RESET}${BLUE}${V}${RESET}${BOLD}$(pad_left "Median " $COL_MED)${RESET}${BLUE}${V}${RESET}${BOLD}$(pad_left "Max " $COL_MAX)${RESET}${BLUE}${V}${RESET}${BOLD}$(pad_left "Cost (USD) " $COL_USD)${RESET}${BLUE}${V}${RESET}"
    echo -e "${BLUE}${LT}$(repeat_char $H $COL_FUNC)${CR}$(repeat_char $H $COL_MIN)${CR}$(repeat_char $H $COL_AVG)${CR}$(repeat_char $H $COL_MED)${CR}$(repeat_char $H $COL_MAX)${CR}$(repeat_char $H $COL_USD)${RT}${RESET}"
}

# Function to print table row
print_table_row() {
    local func="$1"
    local min="$2"
    local avg="$3"
    local med="$4"
    local max="$5"
    local usd="$6"

    # Color code based on cost
    local cost_color="${GREEN}"
    local cost_num=$(echo "$usd" | sed 's/[^0-9.]//g')
    if [ -n "$cost_num" ]; then
        if [ "$(echo "$cost_num > 10" | bc 2>/dev/null)" -eq 1 ] 2>/dev/null; then
            cost_color="${RED}"
        elif [ "$(echo "$cost_num > 1" | bc 2>/dev/null)" -eq 1 ] 2>/dev/null; then
            cost_color="${YELLOW}"
        fi
    fi

    echo -e "${BLUE}${V}${RESET} $(pad_right "$func" $((COL_FUNC-1)))${BLUE}${V}${RESET}${DIM}$(pad_left "$(format_number $min)" $COL_MIN)${RESET}${BLUE}${V}${RESET}${WHITE}$(pad_left "$(format_number $avg)" $COL_AVG)${RESET}${BLUE}${V}${RESET}${DIM}$(pad_left "$(format_number $med)" $COL_MED)${RESET}${BLUE}${V}${RESET}${DIM}$(pad_left "$(format_number $max)" $COL_MAX)${RESET}${BLUE}${V}${RESET}${cost_color}$(pad_left "$usd " $COL_USD)${RESET}${BLUE}${V}${RESET}"
}

# Function to print table footer
print_table_footer() {
    echo -e "${BLUE}${BL}$(repeat_char $H $COL_FUNC)${BT}$(repeat_char $H $COL_MIN)${BT}$(repeat_char $H $COL_AVG)${BT}$(repeat_char $H $COL_MED)${BT}$(repeat_char $H $COL_MAX)${BT}$(repeat_char $H $COL_USD)${BR}${RESET}"
}

# Print header
echo -e "${BOLD}${MAGENTA}"
echo "  ╔═══════════════════════════════════════════════════════════════════════════════════════╗"
echo "  ║                                                                                       ║"
echo "  ║   ⛽  GAS ESTIMATIONS REPORT                                                          ║"
echo "  ║                                                                                       ║"
echo "  ╚═══════════════════════════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "  ${DIM}Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')${RESET}"
echo ""

# Network conditions box
echo -e "  ${CYAN}${BOLD}📊 Network Conditions${RESET}"
echo -e "  ${BLUE}${TL}$(repeat_char $H 25)${TT}$(repeat_char $H 20)${TR}${RESET}"
echo -e "  ${BLUE}${V}${RESET} $(pad_right "Parameter" 24)${BLUE}${V}${RESET}$(pad_left "${GAS_PRICE_GWEI} gwei" 19) ${BLUE}${V}${RESET}"
echo -e "  ${BLUE}${LT}$(repeat_char $H 25)${CR}$(repeat_char $H 20)${RT}${RESET}"
echo -e "  ${BLUE}${V}${RESET} $(pad_right "Gas Price" 24)${BLUE}${V}${RESET}${YELLOW}$(pad_left "${GAS_PRICE_GWEI} gwei" 19) ${RESET}${BLUE}${V}${RESET}"
echo -e "  ${BLUE}${V}${RESET} $(pad_right "ETH Price" 24)${BLUE}${V}${RESET}${GREEN}$(pad_left "\$${ETH_PRICE}" 19) ${RESET}${BLUE}${V}${RESET}"
echo -e "  ${BLUE}${BL}$(repeat_char $H 25)${BT}$(repeat_char $H 20)${BR}${RESET}"
echo ""

# Also write to file (without colors for markdown)
{
    echo "# ⛽ Gas Estimations Report"
    echo ""
    echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
    echo "## 📊 Network Conditions"
    echo ""
    echo "| Parameter | Value |"
    echo "|-----------|-------|"
    echo "| Gas Price | ${GAS_PRICE_GWEI} gwei |"
    echo "| ETH Price | \$${ETH_PRICE} |"
    echo ""
    echo "---"
    echo ""
    echo "## 📋 Contract Gas Costs"
    echo ""
} > "$OUTPUT_FILE"

current_contract=""
current_path=""
in_function_section=0
deployment_cost=""
deployment_size=""
skip_contract=0
first_contract=1
function_rows=()

while IFS= read -r line; do
    # Detect contract header (contains "Contract" at the end)
    if echo "$line" | grep -qE "\.sol:[A-Za-z0-9_]+ Contract"; then
        # Print previous contract's table footer if needed
        if [ $in_function_section -eq 1 ]; then
            print_table_footer
            echo ""
            # Write rows to file
            for row in "${function_rows[@]}"; do
                echo "$row" >> "$OUTPUT_FILE"
            done
            echo "" >> "$OUTPUT_FILE"
        fi

        # Extract full path
        current_path=$(echo "$line" | sed -E 's/.*\| ([^|]+\.sol):[A-Za-z0-9_]+ Contract.*/\1/' | sed 's/^[[:space:]]*//')
        # Extract contract name
        current_contract=$(echo "$line" | sed -E 's/.*\.sol:([A-Za-z0-9_]+) Contract.*/\1/')
        in_function_section=0
        deployment_cost=""
        deployment_size=""
        function_rows=()

        # Skip if not in src/, or if in vendor/, base/, or test/
        skip_contract=0
        if ! echo "$current_path" | grep -qE "^src/"; then
            skip_contract=1
        elif echo "$current_path" | grep -qE "^src/vendor/"; then
            skip_contract=1
        elif echo "$current_path" | grep -qE "^src/base/"; then
            skip_contract=1
        elif echo "$current_path" | grep -qE "^test/"; then
            skip_contract=1
        fi
        continue
    fi

    # Skip if we're ignoring this contract
    if [ $skip_contract -eq 1 ]; then
        continue
    fi

    # Detect deployment cost line (after "Deployment Cost" header)
    if echo "$line" | grep -qE "^\| Deployment Cost"; then
        continue
    fi

    # Parse deployment cost row (numbers only line after deployment header)
    if [ -n "$current_contract" ] && [ $in_function_section -eq 0 ] && echo "$line" | grep -qE "^\|[[:space:]]+[0-9]+"; then
        deployment_cost=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
        deployment_size=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')
        continue
    fi

    # Detect function name header
    if echo "$line" | grep -qE "^\| Function Name"; then
        in_function_section=1

        # Print contract header
        echo -e "  ${BOLD}${GREEN}📄 $current_contract${RESET}"
        echo -e "  ${DIM}$current_path${RESET}"

        if [ -n "$deployment_cost" ] && [[ "$deployment_cost" =~ ^[0-9]+$ ]]; then
            deploy_usd=$(calc_usd "$deployment_cost")
            deploy_usd_fmt=$(format_usd "$deploy_usd")
            echo -e "  ${CYAN}Deployment:${RESET} $(format_number $deployment_cost) gas ${DIM}(~${deploy_usd_fmt})${RESET} ${CYAN}Size:${RESET} $(format_number $deployment_size) bytes"
        fi
        echo ""

        print_table_header

        # Write to file
        {
            echo "### 📄 $current_contract"
            echo ""
            echo "**Path:** \`$current_path\`"
            echo ""
            if [ -n "$deployment_cost" ] && [[ "$deployment_cost" =~ ^[0-9]+$ ]]; then
                echo "**Deployment:** $(format_number $deployment_cost) gas (~${deploy_usd_fmt}) | **Size:** $(format_number $deployment_size) bytes"
            fi
            echo ""
            echo "| Function | Min | Avg | Median | Max | Cost (USD) |"
            echo "|:---------|----:|----:|-------:|----:|-----------:|"
        } >> "$OUTPUT_FILE"

        continue
    fi

    # Parse function rows
    if [ $in_function_section -eq 1 ] && echo "$line" | grep -qE "^\|[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]+\|"; then
        # Skip separator lines
        if echo "$line" | grep -qE "^\|[-]+\|"; then
            continue
        fi

        func_name=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
        min_gas=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')
        avg_gas=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4}')
        median_gas=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $5); print $5}')
        max_gas=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $6); print $6}')

        # Skip if not valid numbers
        if ! [[ "$avg_gas" =~ ^[0-9]+$ ]]; then
            continue
        fi

        avg_cost_usd=$(calc_usd "$avg_gas")
        avg_cost_formatted=$(format_usd "$avg_cost_usd")

        print_table_row "$func_name" "$min_gas" "$avg_gas" "$median_gas" "$max_gas" "$avg_cost_formatted"

        # Store for file output
        function_rows+=("| $func_name | $(format_number $min_gas) | $(format_number $avg_gas) | $(format_number $median_gas) | $(format_number $max_gas) | $avg_cost_formatted |")
    fi

    # End of table detection
    if echo "$line" | grep -qE "^╰"; then
        if [ $in_function_section -eq 1 ]; then
            print_table_footer
            echo ""
            # Write rows to file
            for row in "${function_rows[@]}"; do
                echo "$row" >> "$OUTPUT_FILE"
            done
            echo "" >> "$OUTPUT_FILE"
            function_rows=()
        fi
        in_function_section=0
    fi
done < "$TEMP_FILE"

# Print last table footer if needed
if [ $in_function_section -eq 1 ]; then
    print_table_footer
    echo ""
    for row in "${function_rows[@]}"; do
        echo "$row" >> "$OUTPUT_FILE"
    done
    echo "" >> "$OUTPUT_FILE"
fi

# Footer
{
    echo "---"
    echo ""
    echo "> **Note:** Gas costs are estimates based on current network conditions. Actual costs may vary."
    echo ">"
    echo "> *Only showing contracts from \`src/\` directory (excluding \`vendor/\` and \`base/\` contracts).*"
} >> "$OUTPUT_FILE"

echo -e "${DIM}────────────────────────────────────────────────────────────────────────────────────────────${RESET}"
echo ""
echo -e "  ${GREEN}${BOLD}✅ Gas estimations saved to:${RESET} ${CYAN}$OUTPUT_FILE${RESET}"
echo ""
echo -e "  ${DIM}Legend: ${GREEN}■${RESET}${DIM} < \$1  ${YELLOW}■${RESET}${DIM} \$1-\$10  ${RED}■${RESET}${DIM} > \$10${RESET}"
echo ""

# Cleanup
rm -f "$TEMP_FILE"
