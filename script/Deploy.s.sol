// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/SoulBoundIdentityNFT.sol";
import "../src/BondFactory.sol";
import "../src/BondOracle.sol";
import "../src/SyntheticRubble.sol";

contract DeployScript is Script {
    uint256 constant INITIAL_FUNDING_AMOUNT = 0.5 ether;

    // Read private keys from environment
    uint256 fundingPrivateKey = vm.envUint("FUNDING_PRIVATE_KEY");
    uint256 protocolDeployerPrivateKey = vm.envUint("PROTOCOL_DEPLOYER_PRIVATE_KEY");
    uint256 identityMinterPrivateKey = vm.envUint("IDENTITY_MINTER_PRIVATE_KEY");
    uint256 bondIssuerPrivateKey = vm.envUint("BOND_ISSUER_PRIVATE_KEY");
    uint256 priceFeedUpdaterPrivateKey = vm.envUint("PRICE_FEED_UPDATER_PRIVATE_KEY");

    // Derive addresses from private keys
    address funding = vm.addr(fundingPrivateKey);
    address protocolDeployer = vm.addr(protocolDeployerPrivateKey);
    address identityMinter = vm.addr(identityMinterPrivateKey);
    address bondIssuer = vm.addr(bondIssuerPrivateKey);
    address priceFeedUpdater = vm.addr(priceFeedUpdaterPrivateKey);

    // Base URI for the SoulBoundIdentityNFT metadata

    function run()
        external
        returns (
            SoulBoundIdentityNFT soulBoundIdentityNFT,
            BondFactory bondFactory,
            BondOracle bondOracle,
            SyntheticRubble srub
        )
    {
        string memory BASE_URI = vm.envString("BASE_URI");

        // Log generated addresses and private keys
        console.log("Addresses:");
        console.log("\tProtocol Deployer:", protocolDeployer);
        console.log("\tIdentity Minter:", identityMinter);
        console.log("\tBond Issuer:", bondIssuer);
        console.log("\tPrice Feed Updater:", priceFeedUpdater);

        console.log("Funding:", funding);

        console.log("BASE_URI:", BASE_URI);

        uint256 fundingBalance = funding.balance;
        console.log("Funding balance:", fundingBalance);

        if (fundingBalance < INITIAL_FUNDING_AMOUNT * 4) {
            console.log("Insufficient funding balance, expected at least", INITIAL_FUNDING_AMOUNT * 4);
            revert("Insufficient funding balance");
        }

        vm.startBroadcast(fundingPrivateKey);

        payable(protocolDeployer).transfer(INITIAL_FUNDING_AMOUNT);
        console.log("Transferred some ETH to Protocol Deployer");

        payable(identityMinter).transfer(INITIAL_FUNDING_AMOUNT);
        console.log("Transferred some ETH to Identity Minter");

        payable(bondIssuer).transfer(INITIAL_FUNDING_AMOUNT);
        console.log("Transferred some ETH to Bond Issuer");

        payable(priceFeedUpdater).transfer(INITIAL_FUNDING_AMOUNT);
        console.log("Transferred some ETH to Price Feed Updater");

        vm.stopBroadcast();

        vm.startBroadcast(protocolDeployerPrivateKey);

        bondFactory = new BondFactory(
            bondIssuer // initialIssuer
        );
        console.log("BondFactory deployed at:", address(bondFactory));

        bondOracle = new BondOracle(address(bondFactory), priceFeedUpdater);
        console.log("BondOracle deployed at:", address(bondOracle));

        soulBoundIdentityNFT = new SoulBoundIdentityNFT(identityMinter, BASE_URI);
        console.log("SoulBoundIdentityNFT deployed at:", address(soulBoundIdentityNFT));

        bondFactory.setDependencies(address(bondOracle), address(soulBoundIdentityNFT));
        console.log("Dependencies set in BondFactory");

        srub = new SyntheticRubble(address(bondOracle));
        console.log("sRUB deployed at:", address(srub));

        vm.stopBroadcast();

        vm.startBroadcast(identityMinterPrivateKey);

        soulBoundIdentityNFT.mint(address(srub), 365 days);
        console.log("Minted KYC NFT to sRUB");
        vm.stopBroadcast();
    }
}
