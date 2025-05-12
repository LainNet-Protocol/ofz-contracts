# Onchain Price Publisher Service

This service periodically fetches OFZ (Russian Federal Loan Bonds) price data, complete with cryptographic signatures, from the `OffchainPriceProvider` service. It then compares these prices with the current prices stored in the `BondOracle` smart contract. If a price deviation exceeds a configurable threshold (e.g., 1%), the service calls the `BondOracle` contract to update the price on the blockchain.

This service is designed to work in conjunction with the `OffchainPriceProvider` and the `BondOracle.sol` smart contract (developed using Foundry).

## Features

- Periodically fetches signed OFZ prices from the `OffchainPriceProvider`.
- Retrieves current on-chain prices from the `BondOracle` smart contract.
- Compares off-chain and on-chain prices.
- Updates prices on the `BondOracle` smart contract if the change exceeds a configurable percentage threshold.
- Uses `web3.py` for Ethereum blockchain interaction.
- Configurable via environment variables.
- Comprehensive logging for monitoring and troubleshooting.

## Installation

1.  **Clone the repository** (if you haven't already) and navigate to this service's directory:
    ```bash
    # cd /path/to/your/project/backend/OnchainPricePublisher
    ```

2.  **Install dependencies:**
    Make sure you have Python 3.7+ installed.
    ```bash
    pip install -r requirements.txt
    ```

3.  **Set up environment variables:**
    Create a `.env` file in the `backend/OnchainPricePublisher/` directory or set the following environment variables in your system:

    ```bash
    # Required:
    ONCHAIN_PUBLISHER_BOND_ORACLE_ADDRESS="0xYourBondOracleContractAddress"
    ONCHAIN_PUBLISHER_ETHEREUM_RPC_URL="https://your.ethereum.rpc.url"
    ONCHAIN_PUBLISHER_PRIVATE_KEY="your_publisher_ethereum_account_private_key" # For sending transactions

    # Optional (defaults are provided in config.py):
    ONCHAIN_PUBLISHER_OFFCHAIN_PROVIDER_URL="http://127.0.0.1:5000/api/prices?sign=true" # URL of your OffchainPriceProvider
    ONCHAIN_PUBLISHER_POLL_INTERVAL_SECONDS="60"  # How often to check for price updates
    ONCHAIN_PUBLISHER_PRICE_CHANGE_THRESHOLD_PERCENT="1.0" # Min % change to trigger update
    ONCHAIN_PUBLISHER_BOND_ORACLE_ABI_PATH="../../out/BondOracle.sol/BondOracle.json" # Path to ABI
    ONCHAIN_PUBLISHER_LOG_LEVEL="INFO" # Logging level (DEBUG, INFO, WARNING, ERROR)
    ONCHAIN_PUBLISHER_CHAIN_ID="" # e.g., "1" for Ethereum Mainnet, "4" for Rinkeby. Often inferred by web3.py.
    ```
    **Note:** The `PUBLISHER_PRIVATE_KEY` is for the account that will pay gas fees to call the `BondOracle` contract. This account does *not* need the `PRICE_FEED_UPDATER_ROLE` in the `BondOracle` contract if using `updatePriceFeedWithSignature`. The signature provided by the `OffchainPriceProvider` comes from an account that *does* have that role.

## Usage

Once dependencies are installed and environment variables are configured:

1.  Navigate to the service directory:
    ```bash
    cd backend/OnchainPricePublisher
    ```

2.  Run the publisher script:
    ```bash
    python publisher.py
    ```

The service will start, perform an initial price check and update cycle, and then continue to run periodically based on `ONCHAIN_PUBLISHER_POLL_INTERVAL_SECONDS`. Check the console output for logs.

## Testing with Anvil (Local Development)

Anvil is a local Ethereum node included with Foundry, perfect for development and testing. Here's how to run the `OnchainPricePublisher` service with Anvil:

1.  **Start Anvil:**
    Open a new terminal window and start Anvil. It will typically run on `http://127.0.0.1:8545`.
    ```bash
    anvil
    ```
    Anvil will output a list of available accounts and their private keys. Keep this terminal window open.

2.  **Deploy `BondOracle.sol` to Anvil:**
    In another terminal, navigate to the root of your Foundry project (where `foundry.toml` is located).
    Deploy your `BondOracle` contract using Foundry's `forge create` or a deployment script. For example:
    ```bash
    forge create --rpc-url http://127.0.0.1:8545 --private-key <ANVIL_DEPLOYER_PRIVATE_KEY> src/BondOracle.sol:BondOracle --constructor-args <BOND_FACTORY_ADDRESS_ON_ANVIL> <INITIAL_PRICE_FEED_MANAGER_ON_ANVIL> <INITIAL_PRICE_FEED_UPDATER_ON_ANVIL_SIGNER_ADDRESS>
    ```
    - Replace `<ANVIL_DEPLOYER_PRIVATE_KEY>` with one of the private keys provided by Anvil when it started.
    - Replace constructor arguments with appropriate addresses. The `<INITIAL_PRICE_FEED_UPDATER_ON_ANVIL_SIGNER_ADDRESS>` should be the address corresponding to the private key your `OffchainPriceProvider` will use for signing when running in your local test setup.
    - Note the deployed `BondOracle` contract address from the output.

3.  **Configure `OffchainPriceProvider` for Anvil:**
    - Ensure your `OffchainPriceProvider` service is running.
    - Configure its `ETH_PRIVATE_KEY` environment variable to use a private key from Anvil whose corresponding address has been granted the `PRICE_FEED_UPDATER_ROLE` on the `BondOracle` contract deployed to Anvil. This is the `<INITIAL_PRICE_FEED_UPDATER_ON_ANVIL_SIGNER_ADDRESS>` used in the `forge create` command.

4.  **Configure `OnchainPricePublisher` for Anvil:**
    Update your `.env` file in `backend/OnchainPricePublisher/` with the following:
    ```env
    ONCHAIN_PUBLISHER_BOND_ORACLE_ADDRESS="<YOUR_ANVIL_BOND_ORACLE_CONTRACT_ADDRESS>"
    ONCHAIN_PUBLISHER_ETHEREUM_RPC_URL="http://127.0.0.1:8545"
    ONCHAIN_PUBLISHER_PRIVATE_KEY="<ANVIL_PUBLISHER_ACCOUNT_PRIVATE_KEY>" # Use a different Anvil private key for the publisher
    ONCHAIN_PUBLISHER_CHAIN_ID="31337" # Default Anvil Chain ID
    
    # Ensure OffchainPriceProvider URL is accessible, e.g.:
    # ONCHAIN_PUBLISHER_OFFCHAIN_PROVIDER_URL="http://127.0.0.1:5000/api/prices?sign=true" 
    ```
    - Replace `<YOUR_ANVIL_BOND_ORACLE_CONTRACT_ADDRESS>` with the address from step 2.
    - Replace `<ANVIL_PUBLISHER_ACCOUNT_PRIVATE_KEY>` with another private key from the Anvil startup output (different from the deployer or the off-chain signer if possible, though Anvil accounts have plenty of ETH).

5.  **Run `OnchainPricePublisher`:**
    In its directory (`backend/OnchainPricePublisher`), start the service:
    ```bash
    python publisher.py
    ```
    The publisher should now connect to your local Anvil node and interact with the `BondOracle` contract you deployed. You will see transaction logs in the Anvil terminal.

**Important Considerations for Anvil Testing:**
- **Contract State:** Anvil starts with a fresh state each time unless you are using snapshotting or forking features. You'll need to redeploy your contracts and re-configure roles if you restart Anvil.
- **`secid` Registration:** Ensure that `secid`s are registered in your `BondOracle` contract on Anvil (e.g., via `addPriceFeed` called by your `BondFactory` deployment logic) so the publisher can find the corresponding bond addresses.
- **OffchainPriceProvider Data:** The `OffchainPriceProvider` will still fetch real data from MOEX unless you modify it to serve mock data for testing. The signatures it provides must come from an account recognized by your Anvil-deployed `BondOracle` as a `PRICE_FEED_UPDATER_ROLE` holder.

## Operation Details

1.  **Initialization:**
    - Loads configuration from environment variables.
    - Connects to the specified Ethereum RPC endpoint.
    - Loads the `BondOracle` smart contract ABI and address.
    - Sets up the Ethereum account (from `ONCHAIN_PUBLISHER_PRIVATE_KEY`) that will be used to send transactions.

2.  **Scheduled Task (Price Update Cycle):**
    - **Fetch Off-chain Data:** Makes an HTTP GET request to the `ONCHAIN_PUBLISHER_OFFCHAIN_PROVIDER_URL` to get the latest OFZ prices and their signatures.
    - **Process Each Security (`secid`):**
        - **Get On-chain Price:** Queries the `BondOracle` contract using `secidToBond(secid)` to get the bond token address, then `getPriceFeed(bondAddress)` to get the `lastPrice`.
        - **Compare Prices:** Calculates the percentage difference between the new off-chain price and the current on-chain price.
        - **Update On-chain (if necessary):** If the price difference meets or exceeds `ONCHAIN_PUBLISHER_PRICE_CHANGE_THRESHOLD_PERCENT`, or if there's no current on-chain price, it constructs and sends a transaction to the `BondOracle` contract's `updatePriceFeedWithSignature` function. This function takes the `secid`, the new `price_uint`, and the `signature` obtained from the off-chain provider.

3.  **Signature Handling:**
    - The `OnchainPricePublisher` service **does not generate** cryptographic signatures.
    - It receives pre-signed price data from the `OffchainPriceProvider`.
    - The `BondOracle.updatePriceFeedWithSignature` function on the smart contract is responsible for recovering the signer's address from the provided signature and `secid`/`price` data. It then verifies if this recovered signer has the `PRICE_FEED_UPDATER_ROLE`.
    - The Ethereum account used by `OnchainPricePublisher` (configured via `ONCHAIN_PUBLISHER_PRIVATE_KEY`) only needs to have enough funds to pay for the gas fees of the transaction.

## Logging

The service uses Python's `logging` module. By default, logs are printed to standard output. The log level can be configured using the `ONCHAIN_PUBLISHER_LOG_LEVEL` environment variable.

## Smart Contract Interaction

-   **ABI:** The ABI for the `BondOracle` contract is expected to be at the path specified by `ONCHAIN_PUBLISHER_BOND_ORACLE_ABI_PATH` (default: `../../out/BondOracle.sol/BondOracle.json` within the service directory).
-   **Functions Used:**
    -   `secidToBond(string memory _secid) view returns (address)`: To get the bond token address for a given `secid`.
    -   `getPriceFeed(address _feed) view returns (BondInfo memory)`: To get the current price and other info for a bond token.
    -   `updatePriceFeedWithSignature(string calldata _secid, uint160 _price, bytes calldata _signature)`: To submit a new price update.

Ensure your `BondOracle.sol` contract is deployed and its address is correctly set in the environment variables. The account providing signatures in the `OffchainPriceProvider` must have the `PRICE_FEED_UPDATER_ROLE` in the `BondOracle` contract.
