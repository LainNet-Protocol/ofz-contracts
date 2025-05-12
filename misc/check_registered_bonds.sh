#!/bin/bash

# Color codes for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========== Checking Registered Bonds in BondOracle ==========${NC}"

# Function to display error and exit
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Check if necessary tools are installed
command -v cast >/dev/null 2>&1 || error_exit "Cast is not installed. Please install Foundry."

# Default parameters
RPC_URL=${1:-"http://127.0.0.1:8545"}
BOND_ORACLE_ADDRESS=${2:-""}

# If BOND_ORACLE_ADDRESS is not provided, try to find it from env or previous runs
if [ -z "$BOND_ORACLE_ADDRESS" ]; then
    # Try to read from OnchainPricePublisher env files if they exist
    if [ -f "backend/OnchainPricePublisher/.env" ]; then
        BOND_ORACLE_ADDRESS=$(grep "ONCHAIN_PUBLISHER_BOND_ORACLE_ADDRESS" backend/OnchainPricePublisher/.env | cut -d'=' -f2)
    elif [ -f "backend/OnchainPricePublisher/.env.example" ]; then
        BOND_ORACLE_ADDRESS=$(grep "ONCHAIN_PUBLISHER_BOND_ORACLE_ADDRESS" backend/OnchainPricePublisher/.env.example | cut -d'=' -f2)
    fi
    
    # If still empty, try OffchainPriceProvider env files
    if [ -z "$BOND_ORACLE_ADDRESS" ]; then
        if [ -f "backend/OffchainPriceProvider/.env" ]; then
            BOND_ORACLE_ADDRESS=$(grep "OFFCHAIN_PROVIDER_BOND_ORACLE_ADDRESS" backend/OffchainPriceProvider/.env | cut -d'=' -f2)
        elif [ -f "backend/OffchainPriceProvider/.env.example" ]; then
            BOND_ORACLE_ADDRESS=$(grep "OFFCHAIN_PROVIDER_BOND_ORACLE_ADDRESS" backend/OffchainPriceProvider/.env.example | cut -d'=' -f2)
        fi
    fi
    
    # If still empty, ask user
    if [ -z "$BOND_ORACLE_ADDRESS" ]; then
        read -p "Enter BondOracle contract address: " BOND_ORACLE_ADDRESS
    fi
fi

echo -e "${YELLOW}Using BondOracle address: $BOND_ORACLE_ADDRESS${NC}"
echo -e "${YELLOW}RPC URL: $RPC_URL${NC}"

# Check bond factory address
if [ -f "backend/OnchainPricePublisher/.env" ]; then
    BOND_FACTORY_ADDRESS=$(grep "BOND_FACTORY_ADDRESS" backend/OnchainPricePublisher/.env | cut -d'=' -f2)
elif [ -f "backend/OnchainPricePublisher/.env.example" ]; then
    BOND_FACTORY_ADDRESS=$(grep "BOND_FACTORY_ADDRESS" backend/OnchainPricePublisher/.env.example | cut -d'=' -f2)
fi

if [ -n "$BOND_FACTORY_ADDRESS" ]; then
    echo -e "${YELLOW}BondFactory address: $BOND_FACTORY_ADDRESS${NC}"
fi

# Get test SECIDs to check
TEST_SECIDS=(
    "SU52005RMFS4"
    "SU26240RMFS6"
    "SU26241RMFS4"
)

echo -e "${YELLOW}Checking if test SECIDs are registered in BondOracle...${NC}"

# Function to debug a specific SECID
debug_secid() {
    local secid=$1
    
    echo -e "\n${BLUE}=== Debugging SECID: $secid ===${NC}"
    
    # Check the exact string value as stored in the contract
    echo -e "${YELLOW}Checking SECID in different formats...${NC}"
    
    # Original format
    echo -e "${YELLOW}Original: $secid${NC}"
    BOND_ADDRESS=$(cast call --rpc-url $RPC_URL $BOND_ORACLE_ADDRESS "secidToBond(string)(address)" "$secid" 2>/dev/null || echo "Error")
    if [[ $BOND_ADDRESS == "0x0000000000000000000000000000000000000000" || $BOND_ADDRESS == "Error" ]]; then
        echo -e "${RED}✗ Not registered with exact format: $secid${NC}"
    else
        echo -e "${GREEN}✓ Registered with exact format: $secid => $BOND_ADDRESS${NC}"
        return
    fi
    
    # Try lowercase
    LOWER_SECID=$(echo "$secid" | tr '[:upper:]' '[:lower:]')
    echo -e "${YELLOW}Lowercase: $LOWER_SECID${NC}"
    BOND_ADDRESS=$(cast call --rpc-url $RPC_URL $BOND_ORACLE_ADDRESS "secidToBond(string)(address)" "$LOWER_SECID" 2>/dev/null || echo "Error")
    if [[ $BOND_ADDRESS == "0x0000000000000000000000000000000000000000" || $BOND_ADDRESS == "Error" ]]; then
        echo -e "${RED}✗ Not registered with lowercase: $LOWER_SECID${NC}"
    else
        echo -e "${GREEN}✓ Registered with lowercase: $LOWER_SECID => $BOND_ADDRESS${NC}"
        return
    fi
    
    # Try with spaces
    SPACED_SECID="$secid "
    echo -e "${YELLOW}With space: '$SPACED_SECID'${NC}"
    BOND_ADDRESS=$(cast call --rpc-url $RPC_URL $BOND_ORACLE_ADDRESS "secidToBond(string)(address)" "$SPACED_SECID" 2>/dev/null || echo "Error")
    if [[ $BOND_ADDRESS == "0x0000000000000000000000000000000000000000" || $BOND_ADDRESS == "Error" ]]; then
        echo -e "${RED}✗ Not registered with trailing space: '$SPACED_SECID'${NC}"
    else
        echo -e "${GREEN}✓ Registered with trailing space: '$SPACED_SECID' => $BOND_ADDRESS${NC}"
        return
    fi
    
    echo -e "${RED}Could not find any registration for this SECID.${NC}"
}

# Check each SECID
for SECID in "${TEST_SECIDS[@]}"; do
    echo -e "\n${YELLOW}Checking SECID: $SECID${NC}"
    
    # Call secidToBond function to check registration
    BOND_ADDRESS=$(cast call --rpc-url $RPC_URL $BOND_ORACLE_ADDRESS "secidToBond(string)(address)" "$SECID" 2>/dev/null || echo "Error")
    
    if [[ $BOND_ADDRESS == "Error" ]]; then
        echo -e "${RED}Error calling secidToBond for $SECID${NC}"
    elif [[ $BOND_ADDRESS == "0x0000000000000000000000000000000000000000" ]]; then
        echo -e "${RED}✗ SECID $SECID is NOT registered (bond address is zero)${NC}"
        debug_secid "$SECID"
    else
        echo -e "${GREEN}✓ SECID $SECID is registered with bond address: $BOND_ADDRESS${NC}"
        
        # Get current price
        PRICE_INFO=$(cast call --rpc-url $RPC_URL $BOND_ORACLE_ADDRESS "getPriceFeed(address)(uint160,uint40,uint40)" "$BOND_ADDRESS" 2>/dev/null || echo "Error")
        
        if [[ $PRICE_INFO == "Error" ]]; then
            echo -e "${RED}Error calling getPriceFeed for $BOND_ADDRESS${NC}"
        else
            CURRENT_PRICE=$(echo $PRICE_INFO | cut -d' ' -f1)
            LAST_UPDATED=$(echo $PRICE_INFO | cut -d' ' -f2)
            MATURITY_AT=$(echo $PRICE_INFO | cut -d' ' -f3)
            
            echo -e "${GREEN}Price: $CURRENT_PRICE${NC}"
            echo -e "${GREEN}Last updated: $LAST_UPDATED${NC}"
            echo -e "${GREEN}Maturity: $MATURITY_AT${NC}"
        fi
    fi
done

# Check for any registered SECIDs
echo -e "\n${YELLOW}Looking for any registered SECIDs in events...${NC}"

# Try to get events from the BondOracle contract
echo -e "${YELLOW}Checking for SecidMappingRegistered events...${NC}"
EVENTS=$(cast logs --rpc-url $RPC_URL "SecidMappingRegistered(string,address)" --from-block 0 --to-block latest --address $BOND_ORACLE_ADDRESS 2>/dev/null || echo "Error")

if [[ $EVENTS == "Error" || -z "$EVENTS" ]]; then
    echo -e "${RED}No SecidMappingRegistered events found or error querying events${NC}"
else
    echo -e "${GREEN}Found SecidMappingRegistered events:${NC}"
    echo "$EVENTS"
fi

echo -e "\n${BLUE}========== Check Complete ==========${NC}"
echo -e "${YELLOW}If no SECIDs are registered, you may need to:${NC}"
echo -e "${YELLOW}1. Run ./scripts/issue_bond.sh to create test bonds${NC}"
echo -e "${YELLOW}2. Check for any errors in the bond creation process${NC}"
echo -e "${YELLOW}3. Verify that the SECID format matches what OffchainPriceProvider is sending${NC}"

# Suggest debugging the BondFactory
if [ -n "$BOND_FACTORY_ADDRESS" ]; then
    echo -e "\n${YELLOW}You can check BondFactory events with:${NC}"
    echo -e "${BLUE}cast logs --rpc-url $RPC_URL \"BondCreated(address,string,uint160,uint160,uint40)\" --from-block 0 --to-block latest --address $BOND_FACTORY_ADDRESS${NC}"
fi
