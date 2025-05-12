# LainNet

This repository contains a set of smart contracts for managing bonds and synthetic ruble tokens on the blockchain. The system implements a complete bond issuance and trading platform with KYC/AML compliance through soul-bound NFTs.

## Contract Overview

### 1. BondFactory.sol
Factory contract for creating new bond tokens with:
- Role-based access control for bond issuers
- Bond creation with customizable parameters
- Integration with BondOracle for price feeds
- Bond details management
- Dependency management for oracle and identity NFT

### 2. BondToken.sol
An ERC20 token representing a bond with the following features:
- Fixed maturity price and maturity date
- KYC/AML compliance through soul-bound identity checks
- Restricted transferability (only whitelisted addresses)
- Bond issuer role for minting and redemption management
- Decimal precision of 0 (whole units only)

### 3. BondOracle.sol
Price feed oracle for bonds with:
- EIP-712 signature support for off-chain price updates
- Multiple price feed management
- SECID to bond address mapping
- Maturity price handling
- Role-based access control for price feed updates
- Nonce-based replay protection
- Batch price update functionality

### 4. SoulBoundIdentityNFT.sol
A soul-bound NFT system for identity management with:
- Non-transferable tokens representing user identity
- Expiration-based identity validation
- Sub-account management (up to 16 sub-accounts per main account)
- Role-based access control for minting and revocation
- KYC/AML whitelist functionality
- EIP-721 compliance with transfer restrictions

### 5. SyntheticRubble.sol
A synthetic stablecoin pegged to the Russian Ruble with:
- 6 decimal precision
- Collateralized debt positions (CDP)
- Multiple collateral support (up to 11 different tokens)
- Liquidation mechanism with 10% penalty
- 125% collateralization ratio requirement
- 120% liquidation threshold
- Position health monitoring
- Collateral and debt management functions



## Key Features

1. **KYC/AML Compliance**
   - Soul-bound identity NFTs
   - Whitelist management
   - Sub-account system for institutional users

2. **Bond Management**
   - Customizable bond parameters
   - Maturity price and date tracking
   - Price feed integration
   - Restricted transferability

3. **Synthetic Ruble**
   - Collateralized stablecoin
   - Multiple collateral support
   - Liquidation mechanism
   - Position health monitoring

4. **Security Features**
   - Role-based access control
   - Signature-based price updates
   - Replay protection
   - Transfer restrictions

## Technical Details

- Solidity version: ^0.8.28
- OpenZeppelin contracts integration
- EIP-721 compliance for NFTs
- EIP-712 for typed structured data
- Role-based access control
- Safe math operations

## Dependencies

- OpenZeppelin Contracts
  - AccessControl
  - ERC20
  - ERC721
  - SafeERC20
  - EnumerableSet
  - Strings

## Security Considerations

1. All contracts implement role-based access control
2. Transfer restrictions on soul-bound NFTs
3. Signature verification for price updates
4. Nonce-based replay protection
5. Collateralization ratio checks
6. Liquidation thresholds and penalties

## Usage

1. Deploy SoulBoundIdentityNFT first
2. Deploy BondOracle with factory address
3. Deploy BondFactory with initial issuer
4. Deploy SyntheticRubble with oracle address
5. Set dependencies in BondFactory
6. Start issuing bonds and managing positions

## License

UNLICENSED

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Coverage

```shell
$ forge coverage --report lcov && genhtml --ignore-errors inconsistent lcov.info -o coverage_html
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Deploying LainNet Contracts

To deploy the contracts using the provided deployment script (`script/Deploy.s.sol`), you need to set the following environment variables:

-   `FUNDING_PRIVATE_KEY`: The private key of the account that will fund other accounts with initial ETH.
-   `PROTOCOL_DEPLOYER_PRIVATE_KEY`: The private key of the account that will deploy the contracts.
-   `IDENTITY_MINTER_PRIVATE_KEY`: The private key for the `SoulBoundIdentityNFT`'s minter role.
-   `BOND_ISSUER_PRIVATE_KEY`: The private key for the `BondFactory`'s bond issuer role.
-   `PRICE_FEED_UPDATER_PRIVATE_KEY`: The private key for the `BondOracle`'s price feed updater role.
-   `BASE_URI`: (Required) The base URI string for the `SoulBoundIdentityNFT` metadata (e.g., "https://api.example.com/nft/").

**Example: Deploying to Anvil (Local Testnet)**

1.  **Start Anvil:**
    Open a new terminal window and run:
    ```shell
    anvil
    ```
    Anvil will start a local Ethereum node and display several accounts with their private keys. Choose one of these accounts to be your deployer.

2.  **Set Environment Variables:**
    In the terminal where you will run the deployment script, set the environment variables. For a local Anvil deployment, you can use Anvil's pre-funded accounts.

    For example, if Anvil provides the following accounts:
    ```
    Account #0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000 ETH)
    Private Key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

    Account #1: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000 ETH)
    Private Key: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
    ```

    You would set the variables like this (replace with actual private keys from your Anvil instance):
    ```shell
    export FUNDING_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
    export PROTOCOL_DEPLOYER_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
    export IDENTITY_MINTER_PRIVATE_KEY=0x7c8526c7b3e6d5c2c5b9d5d80365f575793b3232bd2926a0f5046e48a9f0c753
    export BOND_ISSUER_PRIVATE_KEY=0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
    export PRICE_FEED_UPDATER_PRIVATE_KEY=0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092abff54
    export BASE_URI="https://api.example.com/nft/" 
    ```
    *Note: For persistent environment variables, consider adding them to your shell's configuration file (e.g., `.zshrc`, `.bashrc`) or using a `.env` file with a tool like `dotenv` if your workflow supports it (Foundry scripts can directly read from a `.env` file if it's present in the project root).*

3.  **Run the Deployment Script:**
    Anvil typically runs on `http://127.0.0.1:8545`.
    ```shell
    forge script script/Deploy.s.sol:DeployScript --rpc-url http://127.0.0.1:8545 --broadcast --slow -vvvv
    ```
    The `-vvvv` flag provides verbose output. The `--slow` flag ensures transactions are processed in sequence and helps prevent nonce issues.

    For contract verification on Etherscan, you'll need to:
    1. Set your Etherscan API key:
    ```shell
    export ETHERSCAN_API_KEY=your_etherscan_api_key_here
    ```
    2. Add the `--verify` flag to the deployment command:
    ```shell
    forge script script/Deploy.s.sol:DeployScript --rpc-url http://127.0.0.1:8545 --broadcast --slow --verify -vvvv
    ```

4.  **Testing the Deployment:**
    After deployment, you can run the `SimulateUsage.s.sol` script to test the functionality of the deployed contracts. This script:
    - Creates test users and funds them
    - Issues test bonds
    - Mints KYC NFTs
    - Manages sub-accounts
    - Mints bonds to users
    - Tests collateral deposits

    To run the simulation, first set the contract addresses from your deployment:
    ```shell
    export BOND_FACTORY_CONTRACT=<deployed_bond_factory_address>
    export BOND_ORACLE_CONTRACT=<deployed_bond_oracle_address>
    export IDENTITY_NFT_CONTRACT=<deployed_identity_nft_address>
    export SYNTHETIC_RUB_CONTRACT=<deployed_synthetic_rub_address>
    ```

    Then run the simulation:
    ```shell
    forge script script/SimulateUsage.s.sol:SimulateUsage --rpc-url http://127.0.0.1:8545 --broadcast --slow -vvvv
    ```


### Help

```shell
$ forge --help
$ anvil --help
```

## Project Structure

```
project-root/
├── src/                               # Smart contract source code
│   ├── BondFactory.sol                # Bond creation factory
│   ├── BondToken.sol                  # Bond token implementation
│   ├── BondOracle.sol                 # Bond price oracle
│   ├── SoulBoundIdentityNFT.sol       # User identity token
│   ├── SyntheticRubble.sol            # Synthetic RUB stablecoin
│   └── interfaces/                    # Contract interfaces
│       ├── IBondFactory.sol
│       ├── IBondToken.sol
│       ├── IBondOracle.sol
│       ├── ISoulBoundIdentityNFT.sol
│       └── ISyntheticRubble.sol
│
├── script/                            # Deployment and testing scripts
│   ├── Deploy.s.sol                   # Main deployment script
│   └── SimulateUsage.s.sol            # Contract usage simulation
│
├── test/                              # Smart contract tests
│   ├── BondFactory.t.sol
│   ├── BondToken.t.sol
│   ├── BondOracle.t.sol
│   ├── SoulBoundIdentityNFT.t.sol
│   └── SyntheticRubble.t.sol
│
├── lib/                               # Dependencies
│   └── forge-std/                     # Foundry standard library
│
├── .env.example                       # Example environment variables
├── foundry.toml                       # Foundry configuration
└── README.md                          # Project documentation
```
