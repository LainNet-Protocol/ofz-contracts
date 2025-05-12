#!/bin/bash

# Exit script if any command fails
set -e

# Color codes for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========== OFZ Oracle Integration Tests ==========${NC}"

# Function to display error and exit
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Check if necessary tools are installed
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    command -v curl >/dev/null 2>&1 || error_exit "curl is not installed."
    command -v jq >/dev/null 2>&1 || error_exit "jq is not installed. Please install it with 'apt install jq' or 'brew install jq'"
    command -v cast >/dev/null 2>&1 || error_exit "cast is not installed. Please install Foundry."
    echo -e "${GREEN}All prerequisites satisfied.${NC}"
}

# Verify Anvil is running
check_anvil() {
    echo -e "${YELLOW}Checking if Anvil is running...${NC}"
    if ! nc -z localhost 8545 2>/dev/null; then
        error_exit "Anvil is not running. Please start it with ./scripts/setup_test_environment.sh"
    fi
    echo -e "${GREEN}Anvil is running.${NC}"
}

# Check if OffchainPriceProvider is running
check_offchain_provider() {
    echo -e "${YELLOW}Checking OffchainPriceProvider...${NC}"
    HEALTH_RESPONSE=$(curl -s http://localhost:8080/api/health)
    if [ $? -ne 0 ]; then
        error_exit "OffchainPriceProvider is not responding. Please start it with 'cd backend/OffchainPriceProvider && python3 app.py'"
    fi
    
    echo -e "${GREEN}OffchainPriceProvider is running:${NC}"
    echo $HEALTH_RESPONSE | jq . || echo $HEALTH_RESPONSE
}

# Test fetching prices from OffchainPriceProvider
test_offchain_prices() {
    echo -e "${YELLOW}Fetching prices from OffchainPriceProvider...${NC}"
    PRICES_RESPONSE=$(curl -s http://localhost:8080/api/prices)
    if [ $? -ne 0 ]; then
        error_exit "Failed to fetch prices from OffchainPriceProvider"
    fi
    
    # Count number of price entries
    PRICE_COUNT=$(echo $PRICES_RESPONSE | jq '.prices | length')
    echo -e "${GREEN}Successfully fetched $PRICE_COUNT price entries from OffchainPriceProvider${NC}"
    
    # Check if specific test bonds are present
    TEST_SECIDS=("SU52005RMFS4" "SU26240RMFS6" "SU26241RMFS4")
    for SECID in "${TEST_SECIDS[@]}"; do
        PRICE=$(echo $PRICES_RESPONSE | jq -r ".prices.\"$SECID\".price_uint // \"not_found\"")
        if [ "$PRICE" == "not_found" ]; then
            echo -e "${YELLOW}Warning: Test bond $SECID not found in OffchainPriceProvider data${NC}"
        else
            echo -e "${GREEN}✓ Test bond $SECID found with price: $PRICE${NC}"
        fi
    done
}

# Check if BondOracle contract has the test bonds registered
check_bond_oracle() {
    echo -e "${YELLOW}Checking BondOracle contract for registered SECIDs...${NC}"
    
    # Get BondOracle address (first from env, else ask)
    BOND_ORACLE_ADDRESS=${ONCHAIN_PUBLISHER_BOND_ORACLE_ADDRESS:-""}
    if [ -z "$BOND_ORACLE_ADDRESS" ]; then
        read -p "Enter BondOracle contract address: " BOND_ORACLE_ADDRESS
    fi
    
    # Test each SECID
    TEST_SECIDS=("SU52005RMFS4" "SU26240RMFS6" "SU26241RMFS4")
    ALL_REGISTERED=true
    
    for SECID in "${TEST_SECIDS[@]}"; do
        echo -e "${YELLOW}Checking if $SECID is registered...${NC}"
        
        # Call secidToBond function using cast
        BOND_ADDRESS=$(cast call --rpc-url http://localhost:8545 \
          $BOND_ORACLE_ADDRESS \
          "secidToBond(string)(address)" \
          "$SECID" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
        
        if [ "$BOND_ADDRESS" == "0x0000000000000000000000000000000000000000" ]; then
            echo -e "${RED}✗ $SECID is NOT registered in BondOracle${NC}"
            ALL_REGISTERED=false
        else
            echo -e "${GREEN}✓ $SECID is registered with bond address: $BOND_ADDRESS${NC}"
            
            # Get current price
            PRICE_INFO=$(cast call --rpc-url http://localhost:8545 \
              $BOND_ORACLE_ADDRESS \
              "getPriceFeed(address)(uint160,uint40,uint40)" \
              "$BOND_ADDRESS" 2>/dev/null || echo "Error")
            
            if [ "$PRICE_INFO" != "Error" ]; then
                CURRENT_PRICE=$(echo $PRICE_INFO | cut -d' ' -f1)
                LAST_UPDATED=$(echo $PRICE_INFO | cut -d' ' -f2)
                MATURITY_AT=$(echo $PRICE_INFO | cut -d' ' -f3)
                
                echo -e "${GREEN}  Current price: $CURRENT_PRICE${NC}"
                echo -e "${GREEN}  Last updated: $LAST_UPDATED ($(date -d @$LAST_UPDATED))${NC}"
                echo -e "${GREEN}  Maturity: $MATURITY_AT ($(date -d @$MATURITY_AT))${NC}"
            else
                echo -e "${RED}  Failed to fetch price info for $SECID${NC}"
            fi
        fi
    done
    
    if [ "$ALL_REGISTERED" = false ]; then
        echo -e "${YELLOW}Some SECIDs are not registered in BondOracle.${NC}"
        echo -e "${YELLOW}Use ./scripts/issue_bond.sh to register them.${NC}"
    else
        echo -e "${GREEN}All test SECIDs are registered in BondOracle.${NC}"
    fi
}

# Test the OnchainPricePublisher functionality
test_price_update() {
    echo -e "${YELLOW}Testing OnchainPricePublisher functionality...${NC}"
    echo -e "${YELLOW}This test requires OnchainPricePublisher to be running.${NC}"
    
    # Get BondOracle address
    BOND_ORACLE_ADDRESS=${ONCHAIN_PUBLISHER_BOND_ORACLE_ADDRESS:-""}
    if [ -z "$BOND_ORACLE_ADDRESS" ]; then
        read -p "Enter BondOracle contract address: " BOND_ORACLE_ADDRESS
    fi
    
    # Pick a test SECID
    TEST_SECID="SU52005RMFS4"
    
    # 1. Get current bond address
    echo -e "${YELLOW}Getting bond address for $TEST_SECID...${NC}"
    BOND_ADDRESS=$(cast call --rpc-url http://localhost:8545 \
      $BOND_ORACLE_ADDRESS \
      "secidToBond(string)(address)" \
      "$TEST_SECID" 2>/dev/null)
    
    if [ "$BOND_ADDRESS" == "0x0000000000000000000000000000000000000000" ]; then
        echo -e "${RED}$TEST_SECID is not registered. Skipping price update test.${NC}"
        return
    fi
    
    # 2. Get current price from BondOracle
    echo -e "${YELLOW}Getting current price from BondOracle...${NC}"
    PRICE_INFO=$(cast call --rpc-url http://localhost:8545 \
      $BOND_ORACLE_ADDRESS \
      "getPriceFeed(address)(uint160,uint40,uint40)" \
      "$BOND_ADDRESS" 2>/dev/null)
    
    CURRENT_PRICE=$(echo $PRICE_INFO | cut -d' ' -f1)
    echo -e "${GREEN}Current onchain price for $TEST_SECID: $CURRENT_PRICE${NC}"
    
    # 3. Get price from OffchainPriceProvider
    echo -e "${YELLOW}Getting price from OffchainPriceProvider...${NC}"
    PRICE_RESPONSE=$(curl -s "http://localhost:8080/api/prices/$TEST_SECID")
    OFFCHAIN_PRICE=$(echo $PRICE_RESPONSE | jq -r '.price.price_uint')
    
    echo -e "${GREEN}Offchain price for $TEST_SECID: $OFFCHAIN_PRICE${NC}"
    
    # 4. Calculate difference
    if [ -n "$CURRENT_PRICE" ] && [ -n "$OFFCHAIN_PRICE" ] && [ "$CURRENT_PRICE" -gt 0 ]; then
        PRICE_DIFF=$(( (${OFFCHAIN_PRICE#-} - ${CURRENT_PRICE#-}) * 100 / ${CURRENT_PRICE#-} ))
        echo -e "${YELLOW}Price difference: ${PRICE_DIFF}%${NC}"
        
        # 5. Check if OnchainPricePublisher should update the price
        if [ $PRICE_DIFF -ge 1 ] || [ $PRICE_DIFF -le -1 ]; then
            echo -e "${GREEN}Price difference (${PRICE_DIFF}%) meets the threshold for update.${NC}"
            echo -e "${YELLOW}Wait for OnchainPricePublisher to detect and update it...${NC}"
            echo -e "${YELLOW}(This might take up to the configured poll interval)${NC}"
            
            # 6. Wait for price update 
            MAX_WAIT_SECONDS=120
            echo -e "${YELLOW}Waiting up to $MAX_WAIT_SECONDS seconds for price update...${NC}"
            
            for (( i=1; i<=$MAX_WAIT_SECONDS; i++ )); do
                sleep 1
                if [ $((i % 10)) -eq 0 ]; then
                    echo -e "${YELLOW}Waited $i seconds...${NC}"
                    
                    # Check if price was updated
                    NEW_PRICE_INFO=$(cast call --rpc-url http://localhost:8545 \
                      $BOND_ORACLE_ADDRESS \
                      "getPriceFeed(address)(uint160,uint40,uint40)" \
                      "$BOND_ADDRESS" 2>/dev/null)
                    
                    NEW_CURRENT_PRICE=$(echo $NEW_PRICE_INFO | cut -d' ' -f1)
                    
                    if [ "$NEW_CURRENT_PRICE" != "$CURRENT_PRICE" ]; then
                        echo -e "${GREEN}✓ Price updated to $NEW_CURRENT_PRICE after $i seconds${NC}"
                        return
                    fi
                fi
            done
            
            echo -e "${RED}✗ Price was not updated after $MAX_WAIT_SECONDS seconds${NC}"
            echo -e "${YELLOW}Please check if OnchainPricePublisher is running and logs for any errors${NC}"
        else
            echo -e "${YELLOW}Price difference (${PRICE_DIFF}%) is below the threshold (1%).${NC}"
            echo -e "${YELLOW}OnchainPricePublisher should NOT update the price.${NC}"
        fi
    else
        echo -e "${YELLOW}Could not calculate price difference. Initial price may be 0.${NC}"
    fi
}

# Main function to run all tests
main() {
    check_prerequisites
    check_anvil
    check_offchain_provider
    test_offchain_prices
    check_bond_oracle
    
    echo -e "${YELLOW}Do you want to test price updates with OnchainPricePublisher? (y/n)${NC}"
    read -r TEST_PRICE_UPDATES
    
    if [[ $TEST_PRICE_UPDATES =~ ^[Yy]$ ]]; then
        test_price_update
    fi
    
    echo -e "${GREEN}========== INTEGRATION TESTS COMPLETED ==========${NC}"
}

# Run the main function
main
