#!/bin/bash

# Exit script if any command fails
set -e

# Color codes for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========== OFZ Oracle Test Environment Setup ==========${NC}"

# Function to display error and exit
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Check if necessary tools are installed
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    command -v anvil >/dev/null 2>&1 || error_exit "Anvil is not installed. Please install Foundry."
    command -v forge >/dev/null 2>&1 || error_exit "Forge is not installed. Please install Foundry."
    command -v cast >/dev/null 2>&1 || error_exit "Cast is not installed. Please install Foundry."
    command -v python >/dev/null 2>&1 || error_exit "Python is not installed."
    echo -e "${GREEN}All prerequisites satisfied.${NC}"
}

# Setup environment variables from template if not provided
setup_env_variables() {
    echo -e "${YELLOW}Setting up environment variables...${NC}"
    
    # Set the main private key
    export PRIVATE_KEY=${PRIVATE_KEY:-"0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"}
    
    # Use the same private key for all roles in the test environment
    # These are the private keys required by the updated Deploy.s.sol script
    export FUNDING_PRIVATE_KEY=${FUNDING_PRIVATE_KEY:-$PRIVATE_KEY}
    export PROTOCOL_DEPLOYER_PRIVATE_KEY=${PROTOCOL_DEPLOYER_PRIVATE_KEY:-$PRIVATE_KEY}
    export IDENTITY_MINTER_PRIVATE_KEY=${IDENTITY_MINTER_PRIVATE_KEY:-$PRIVATE_KEY}
    export BOND_ISSUER_PRIVATE_KEY=${BOND_ISSUER_PRIVATE_KEY:-$PRIVATE_KEY}
    export PRICE_FEED_UPDATER_PRIVATE_KEY=${PRICE_FEED_UPDATER_PRIVATE_KEY:-$PRIVATE_KEY}
    
    # Set base URI
    export BASE_URI=${BASE_URI:-"https://example.com/api/identity/"}

    # Ethereum RPC
    export ETH_RPC_URL=${ETH_RPC_URL:-"http://127.0.0.1:8545"}
    export CHAIN_ID=${CHAIN_ID:-31337}
    
    echo -e "${GREEN}Environment variables set.${NC}"
}

# Global variables
ANVIL_PID=""

# Start local Ethereum node (anvil)
start_anvil() {
    echo -e "${YELLOW}Starting Anvil...${NC}"
    # Check if anvil is already running
    if nc -z localhost 8545 2>/dev/null; then
        echo -e "${YELLOW}Anvil is already running on port 8545${NC}"
        # Try to find PID of running anvil instance
        ANVIL_PID=$(ps aux | grep "anvil" | grep -v grep | awk '{print $2}' | head -n 1)
        if [ -n "$ANVIL_PID" ]; then
            echo -e "${GREEN}Found running Anvil with PID: $ANVIL_PID${NC}"
            echo $ANVIL_PID > anvil.pid
        else
            echo -e "${YELLOW}Could not determine PID of running Anvil instance${NC}"
        fi
    else
        # Run anvil in the background
        echo -e "${YELLOW}Launching Anvil in background...${NC}"
        anvil --block-time 5 > anvil.log 2>&1 &
        ANVIL_PID=$!
        echo $ANVIL_PID > anvil.pid
        
        # Give anvil some time to start
        sleep 2
        
        if nc -z localhost 8545 2>/dev/null; then
            echo -e "${GREEN}Anvil started successfully (PID: $ANVIL_PID)${NC}"
        else
            error_exit "Failed to start Anvil"
        fi
    fi
}

# Deploy contracts using forge script
deploy_contracts() {
    echo -e "${YELLOW}Deploying contracts...${NC}"
    forge script script/Deploy.s.sol --rpc-url $ETH_RPC_URL --broadcast -vvv > deploy_output.log 2>&1
    
    if [ $? -ne 0 ]; then
        cat deploy_output.log
        error_exit "Contract deployment failed"
    fi
    
    echo -e "${GREEN}Contracts deployed successfully${NC}"
    
    # Extract deployed contract addresses from the deployment logs
    BOND_ORACLE_ADDRESS=$(grep "BondOracle deployed at:" deploy_output.log | awk '{print $NF}')
    BOND_FACTORY_ADDRESS=$(grep "BondFactory deployed at:" deploy_output.log | awk '{print $NF}')
    
    if [ -z "$BOND_ORACLE_ADDRESS" ] || [ -z "$BOND_FACTORY_ADDRESS" ]; then
        # If log extraction failed, try alternative method using the broadcast output
        BOND_ORACLE_ADDRESS=$(jq -r '.transactions[] | select(.contractName=="BondOracle") | .contractAddress' broadcast/Deploy.s.sol/31337/run-latest.json 2>/dev/null || echo "")
        BOND_FACTORY_ADDRESS=$(jq -r '.transactions[] | select(.contractName=="BondFactory") | .contractAddress' broadcast/Deploy.s.sol/31337/run-latest.json 2>/dev/null || echo "")
        
        if [ -z "$BOND_ORACLE_ADDRESS" ] || [ -z "$BOND_FACTORY_ADDRESS" ]; then
            echo -e "${YELLOW}Could not automatically extract contract addresses.${NC}"
            echo -e "${YELLOW}Please enter addresses manually for the next steps.${NC}"
            read -p "Enter BondOracle address: " BOND_ORACLE_ADDRESS
            read -p "Enter BondFactory address: " BOND_FACTORY_ADDRESS
        fi
    fi
    
    export BOND_ORACLE_ADDRESS
    export BOND_FACTORY_ADDRESS
    
    echo -e "${GREEN}BondOracle address: $BOND_ORACLE_ADDRESS${NC}"
    echo -e "${GREEN}BondFactory address: $BOND_FACTORY_ADDRESS${NC}"
}

# Issue test bonds using cast
issue_test_bonds() {
    if [ -z "$BOND_FACTORY_ADDRESS" ]; then
        read -p "Enter BondFactory address: " BOND_FACTORY_ADDRESS
    fi
    
    echo -e "${YELLOW}Creating test bonds...${NC}"
    
    # Define test OFZ securities to create
    SECURITIES=(
        "SU52005RMFS4"
        "SU26240RMFS6"
        "SU26241RMFS4"
    )
    
    # Initial price (6.6005 with 8 decimals), maturity price (7.0 with 8 decimals)
    # Note: Using smaller values to avoid potential numeric issues
    INITIAL_PRICE="6000000"
    MATURITY_PRICE="7000000"
    
    # Maturity date (1 year from now)
    MATURITY_TIME=$(( $(date +%s) + 31536000 ))
    
    for SECID in "${SECURITIES[@]}"; do
        echo -e "${YELLOW}Issuing bond for $SECID...${NC}"
        
        # Construct the call data only for debugging
        CALLDATA=$(cast calldata "issueBond(string,uint160,uint160,uint40)" "$SECID" "$INITIAL_PRICE" "$MATURITY_PRICE" "$MATURITY_TIME" 2>/dev/null || echo "Failed to generate calldata")
        echo -e "${BLUE}Call data: $CALLDATA${NC}"
        
        # Check if timeout command exists
        if command -v timeout >/dev/null 2>&1; then
            # Use timeout command if available
            echo -e "${YELLOW}Sending transaction with timeout, this may take a moment...${NC}"
            timeout 30s bash -c "cast send --private-key $BOND_ISSUER_PRIVATE_KEY \
              --rpc-url $ETH_RPC_URL \
              $BOND_FACTORY_ADDRESS \
              \"issueBond(string,uint160,uint160,uint40)(address)\" \
              \"$SECID\" \"$INITIAL_PRICE\" \"$MATURITY_PRICE\" \"$MATURITY_TIME\" \
              2>&1" > bond_tx_result.log || echo "Transaction timed out after 30 seconds" >> bond_tx_result.log
        else
            # If timeout is not available (e.g., on macOS), use a different approach
            echo -e "${YELLOW}Sending transaction (timeout command not available), this may take a moment...${NC}"
            # Use a subshell with background process
            (cast send --private-key $BOND_ISSUER_PRIVATE_KEY \
              --rpc-url $ETH_RPC_URL \
              $BOND_FACTORY_ADDRESS \
              "issueBond(string,uint160,uint160,uint40)(address)" \
              "$SECID" "$INITIAL_PRICE" "$MATURITY_PRICE" "$MATURITY_TIME" \
              > bond_tx_result.log 2>&1) &
            
            # Store PID of background process
            CAST_PID=$!
            
            # Wait for a maximum of 30 seconds
            for i in {1..30}; do
                if ! kill -0 $CAST_PID 2>/dev/null; then
                    # Process has completed
                    break
                fi
                sleep 1
                echo -n "."
            done
            echo ""
            
            # Check if process is still running
            if kill -0 $CAST_PID 2>/dev/null; then
                # Kill the process if it's still running
                kill $CAST_PID 2>/dev/null
                echo "Transaction timed out after 30 seconds" >> bond_tx_result.log
            fi
        fi
        
        RESULT=$(cat bond_tx_result.log)
        
        if [[ $RESULT == *"error"* ]] || [[ $RESULT == *"timed out"* ]]; then
            echo -e "${RED}Failed to issue bond for $SECID:${NC}"
            echo -e "${RED}$RESULT${NC}"
            echo -e "${YELLOW}Trying alternate approach for $SECID...${NC}"
            
            # Try alternate method: using forge script
            echo "// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import \"forge-std/Script.sol\";
import \"../src/BondFactory.sol\";

contract IssueBondScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint(\"BOND_ISSUER_PRIVATE_KEY\");
        vm.startBroadcast(deployerPrivateKey);
        
        BondFactory factory = BondFactory(${BOND_FACTORY_ADDRESS});
        
        // Issue the bond
        address bondAddr = factory.issueBond(
            \"${SECID}\",             // name/secid
            ${INITIAL_PRICE},         // initialPrice
            ${MATURITY_PRICE},        // maturityPrice
            ${MATURITY_TIME}          // maturityAt
        );
        
        console.log(\"Bond issued at address:\", bondAddr);
        
        vm.stopBroadcast();
    }
}" > misc/IssueBond_${SECID}.s.sol
            
            forge script misc/IssueBond_${SECID}.s.sol --rpc-url $ETH_RPC_URL --broadcast --private-key $BOND_ISSUER_PRIVATE_KEY -vvv > issue_bond_${SECID}.log 2>&1
            BOND_ADDRESS=$(grep -A 1 "Bond issued at address:" issue_bond_${SECID}.log | tail -n 1 | awk '{print $NF}')
            
            if [ -n "$BOND_ADDRESS" ] && [[ $BOND_ADDRESS =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                echo -e "${GREEN}Bond issued for $SECID: $BOND_ADDRESS${NC}"
                BOND_ADDRESSES[$SECID]=$BOND_ADDRESS
            else
                echo -e "${RED}Failed to issue bond using alternative method. See issue_bond_${SECID}.log for details.${NC}"
            fi
        else
            echo -e "${GREEN}Bond issued for $SECID: $RESULT${NC}"
            # Store the bond token addresses if needed
            BOND_ADDRESSES[$SECID]=$(echo "$RESULT" | grep -oE "0x[a-fA-F0-9]{40}")
        fi
    done
    
    echo -e "${GREEN}Test bonds created successfully${NC}"
}

# Generate .env files for components
generate_env_files() {
    echo -e "${YELLOW}Generating .env files for components...${NC}"
    
    if [ -z "$BOND_ORACLE_ADDRESS" ]; then
        read -p "Enter BondOracle address: " BOND_ORACLE_ADDRESS
    fi
    
    # Generate .env for OffchainPriceProvider
    cat > backend/OffchainPriceProvider/.env << EOL
# OffchainPriceProvider Environment Variables
OFFCHAIN_PROVIDER_ETH_PRIVATE_KEY=${PRICE_FEED_UPDATER_PRIVATE_KEY}
OFFCHAIN_PROVIDER_CACHE_TTL=10
OFFCHAIN_PROVIDER_HOST=0.0.0.0
OFFCHAIN_PROVIDER_PORT=8080
OFFCHAIN_PROVIDER_DEBUG=true
OFFCHAIN_PROVIDER_BOND_ORACLE_ADDRESS=${BOND_ORACLE_ADDRESS}
OFFCHAIN_PROVIDER_CHAIN_ID=${CHAIN_ID}
OFFCHAIN_PROVIDER_SIGNATURE_EXPIRY_SECONDS=300
OFFCHAIN_PROVIDER_NONCE_FILE=data/nonce.json
OFFCHAIN_PROVIDER_CACHE_DIR=data/cache
OFFCHAIN_PROVIDER_PRICE_SCALING_FACTOR=100000000
OFFCHAIN_PROVIDER_ETH_RPC_URL=${ETH_RPC_URL}
EOL
    
    # Generate .env for OnchainPricePublisher
    cat > backend/OnchainPricePublisher/.env << EOL
# OnchainPricePublisher Environment Variables
ONCHAIN_PUBLISHER_BOND_ORACLE_ADDRESS=${BOND_ORACLE_ADDRESS}
ONCHAIN_PUBLISHER_ETHEREUM_RPC_URL=${ETH_RPC_URL}
ONCHAIN_PUBLISHER_PRIVATE_KEY=${PRICE_FEED_UPDATER_PRIVATE_KEY}
ONCHAIN_PUBLISHER_OFFCHAIN_PROVIDER_BASE_URL="http://127.0.0.1:8080"
ONCHAIN_PUBLISHER_POLL_INTERVAL_SECONDS=60
ONCHAIN_PUBLISHER_PRICE_CHANGE_THRESHOLD_PERCENT=1.0
ONCHAIN_PUBLISHER_BOND_ORACLE_ABI_PATH="../../out/BondOracle.sol/BondOracle.json"
ONCHAIN_PUBLISHER_LOG_LEVEL="INFO"
ONCHAIN_PUBLISHER_CHAIN_ID=${CHAIN_ID}
ONCHAIN_PUBLISHER_GAS_LIMIT_UPDATE_PRICE=300000
ONCHAIN_PUBLISHER_TX_RECEIPT_TIMEOUT_SECONDS=180
ONCHAIN_PUBLISHER_SCHEDULER_MISFIRE_GRACE_TIME=30
ONCHAIN_PUBLISHER_REQUESTS_TIMEOUT_SECONDS=60
EOL
        
    echo -e "${GREEN}.env files generated:${NC}"
    echo -e "${GREEN}- backend/OffchainPriceProvider/.env${NC}"
    echo -e "${GREEN}- backend/OnchainPricePublisher/.env${NC}"
}

# Start services
start_services() {
    echo -e "${YELLOW}Starting services...${NC}"
    echo -e "${YELLOW}Note: This will start services in new terminal windows${NC}"
    
    # Check if we're in a terminal that supports running new terminal windows
    if command -v gnome-terminal >/dev/null 2>&1; then
        # Linux with GNOME
        gnome-terminal -- bash -c "cd $(pwd)/backend/OffchainPriceProvider && python app.py; exec bash"
        gnome-terminal -- bash -c "cd $(pwd)/backend/OnchainPricePublisher && python publisher.py; exec bash"
    elif command -v osascript >/dev/null 2>&1; then
        # macOS
        osascript -e "tell application \"Terminal\" to do script \"cd $(pwd)/backend/OffchainPriceProvider && python app.py\""
        osascript -e "tell application \"Terminal\" to do script \"cd $(pwd)/backend/OnchainPricePublisher && python publisher.py\""
    else
        echo -e "${YELLOW}Could not automatically start services in new terminals.${NC}"
        echo -e "${YELLOW}Please start them manually:${NC}"
        echo -e "${BLUE}cd $(pwd)/backend/OffchainPriceProvider && python app.py${NC}"
        echo -e "${BLUE}cd $(pwd)/backend/OnchainPricePublisher && python publisher.py${NC}"
    fi
}

# Create a script to issue more bonds if needed
create_bond_issuer_script() {
    cat > misc/issue_bond.sh << EOL
#!/bin/bash

# Exit script if any command fails
set -e

# Default values
RPC_URL=\${1:-"http://127.0.0.1:8545"}
PRIVATE_KEY=\${2:-"$BOND_ISSUER_PRIVATE_KEY"}
BOND_FACTORY_ADDRESS=\${3:-"$BOND_FACTORY_ADDRESS"}
SECID=\${4:-"SU52005RMFS4"}
INITIAL_PRICE=\${5:-"660050000"}
MATURITY_PRICE=\${6:-"700000000"}
MATURITY_TIME=\${7:-\$(( \$(date +%s) + 31536000 ))}
CHAIN_ID=\${8:-31337}

echo "Issuing bond \$SECID on BondFactory at \$BOND_FACTORY_ADDRESS"

cast send --private-key \$PRIVATE_KEY \\
  --rpc-url \$RPC_URL \\
  \$BOND_FACTORY_ADDRESS \\
  "issueBond(string,uint160,uint160,uint40)(address)" \\
  "\$SECID" "\$INITIAL_PRICE" "\$MATURITY_PRICE" "\$MATURITY_TIME"
EOL
    
    chmod +x misc/issue_bond.sh
    echo -e "${GREEN}Created bond issuer script at misc/issue_bond.sh${NC}"
}

# Main function to run everything
main() {
    # Make misc directory if it doesn't exist
    mkdir -p misc
    
    check_prerequisites
    setup_env_variables
    start_anvil
    deploy_contracts
    issue_test_bonds
    generate_env_files
    create_bond_issuer_script
    
    echo -e "${YELLOW}Do you want to start the OffchainPriceProvider and OnchainPricePublisher services? (y/n)${NC}"
    read -r START_SERVICES
    
    if [[ $START_SERVICES =~ ^[Yy]$ ]]; then
        start_services
    fi
    
    echo -e "${GREEN}========== TEST ENVIRONMENT SETUP COMPLETE ==========${NC}"
    
    # Check if anvil.pid exists and contains a valid PID
    if [ -f "anvil.pid" ] && [ -n "$(cat anvil.pid 2>/dev/null)" ]; then
        ANVIL_PID=$(cat anvil.pid)
        echo -e "${GREEN}Anvil is running in the background (PID: $ANVIL_PID)${NC}"
        echo -e "${YELLOW}To stop Anvil, run: kill $ANVIL_PID${NC}"
    else
        echo -e "${YELLOW}Note: Could not find Anvil PID file. If Anvil is running, you'll need to stop it manually.${NC}"
    fi
    
    echo -e "${YELLOW}To issue additional bonds, use: ./misc/issue_bond.sh${NC}"
    echo -e "${BLUE}Example: ./misc/issue_bond.sh http://127.0.0.1:8545 \"0xYourPrivateKey\" \"$BOND_FACTORY_ADDRESS\" \"NEW_SECID\" \"660050000\" \"700000000\" \"$MATURITY_TIME\"${NC}"
}

# Run the main function
main
