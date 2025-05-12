// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/interfaces/IBondFactory.sol";
import "../src/interfaces/IBondToken.sol";
import "../src/interfaces/ISoulBoundIdentityNFT.sol";
import "../src/interfaces/ISyntheticRubble.sol";

contract SimulateUsage is Script {
    // Read private keys from environment
    uint256 fundingPrivateKey = vm.envUint("FUNDING_PRIVATE_KEY");
    uint256 protocolDeployerPrivateKey = vm.envUint("PROTOCOL_DEPLOYER_PRIVATE_KEY");
    uint256 identityMinterPrivateKey = vm.envUint("IDENTITY_MINTER_PRIVATE_KEY");
    uint256 bondIssuerPrivateKey = vm.envUint("BOND_ISSUER_PRIVATE_KEY");
    uint256 priceFeedUpdaterPrivateKey = vm.envUint("PRICE_FEED_UPDATER_PRIVATE_KEY");

    address BOND_FACTORY = vm.envAddress("BOND_FACTORY_CONTRACT");
    address BOND_ORACLE = vm.envAddress("BOND_ORACLE_CONTRACT");
    address IDENTITY_NFT = vm.envAddress("IDENTITY_NFT_CONTRACT");
    address SYNTHETIC_RUB = vm.envAddress("SYNTHETIC_RUB_CONTRACT");

    mapping(string => uint256) internal users;

    function _makeUser(string memory seed) internal returns (uint256 privateKey, address user) {
        if (users[seed] != 0) {
            privateKey = users[seed];
            user = vm.addr(privateKey);
            return (privateKey, user);
        }

        (user, privateKey) = makeAddrAndKey(seed);
        if (user.balance == 0) {
            vm.startBroadcast(fundingPrivateKey);

            payable(user).transfer(0.1 ether);

            vm.stopBroadcast();
        }
        users[seed] = privateKey;
    }

    function run() public {
        if (BOND_FACTORY == address(0)) {
            revert("BOND_FACTORY_CONTRACT is not set");
        }
        if (BOND_ORACLE == address(0)) {
            revert("BOND_ORACLE_CONTRACT is not set");
        }
        if (IDENTITY_NFT == address(0)) {
            revert("IDENTITY_NFT_CONTRACT is not set");
        }
        if (SYNTHETIC_RUB == address(0)) {
            revert("SYNTHETIC_RUB_CONTRACT is not set");
        }

        console.log("Creating users...");
        (, address user1) = _makeUser("user1");
        (uint256 user2PrivateKey, address user2) = _makeUser("user2");
        (uint256 user3PrivateKey, address user3) = _makeUser("user3");
        (, address user4) = _makeUser("user4");

        console.log(user2PrivateKey);
        revert();

        // Issue bonds
        console.log("Issuing bonds...");
        vm.startBroadcast(bondIssuerPrivateKey);

        address bond1 =
            IBondFactory(BOND_FACTORY).issueBond("SU52005RMFS4", 1000 * 1e6, 1199.5 * 1e6, 1999371600 /* 2032-05-11 */ );
        address bond2 = IBondFactory(BOND_FACTORY).issueBond(
            "SU52004RMFS7", 1000 * 1e6, 1398.22 * 1e6, 1963083600 /* 2032-03-17 */
        );
        console.log("Bond1 created at:", bond1);
        console.log("Bond2 created at:", bond2);

        vm.stopBroadcast();

        // Mint KYC NFTs
        console.log("Minting KYC NFTs...");
        vm.startBroadcast(identityMinterPrivateKey);

        ISoulBoundIdentityNFT(IDENTITY_NFT).mint(user1, 365 days);
        ISoulBoundIdentityNFT(IDENTITY_NFT).mint(user2, 30 days);

        vm.stopBroadcast();

        // Add/remove sub-accounts
        console.log("Managing sub-accounts...");
        vm.startBroadcast(user2PrivateKey);

        ISoulBoundIdentityNFT(IDENTITY_NFT).addSubAccount(user3);
        ISoulBoundIdentityNFT(IDENTITY_NFT).addSubAccount(user4);
        ISoulBoundIdentityNFT(IDENTITY_NFT).removeSubAccount(user4);

        vm.stopBroadcast();

        // Mint new bonds
        console.log("Minting bonds to users...");
        vm.startBroadcast(bondIssuerPrivateKey);

        IBondToken(bond1).mint(user1, 1000);
        IBondToken(bond1).mint(user2, 500);
        IBondToken(bond1).mint(user3, 200);

        IBondToken(bond2).mint(user1, 5000);
        IBondToken(bond2).mint(user2, 1000);
        IBondToken(bond2).mint(user3, 200);

        vm.stopBroadcast();

        console.log("Depositing collateral...");
        vm.startBroadcast(user3PrivateKey);

        IBondToken(bond1).approve(SYNTHETIC_RUB, type(uint256).max);
        ISyntheticRubble(SYNTHETIC_RUB).depositCollateral(bond1, 200);

        vm.stopBroadcast();
        console.log("Simulation complete!");
    }
}
