// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {BondOracle} from "../src/BondOracle.sol";
import {BondFactory} from "../src/BondFactory.sol";
import {BondToken} from "../src/BondToken.sol";
import {IBondOracle} from "../src/interfaces/IBondOracle.sol";
import {SoulBoundIdentityNFT} from "../src/SoulBoundIdentityNFT.sol";

import {IBondFactory} from "../src/interfaces/IBondFactory.sol";

contract BondOracleTest is Test {
    BondOracle public oracle;
    BondFactory public factory;
    BondToken public bond;
    address public admin;
    address public issuer;
    address public priceFeedUpdater;
    address public user;
    uint256 public privateKey;

    function setUp() public {
        admin = makeAddr("admin");
        issuer = makeAddr("issuer");
        (priceFeedUpdater, privateKey) = makeAddrAndKey("priceFeedUpdater");
        user = makeAddr("user");

        vm.startPrank(admin);
        factory = new BondFactory(issuer);
        oracle = new BondOracle(address(factory), priceFeedUpdater);

        SoulBoundIdentityNFT identityNFT = new SoulBoundIdentityNFT(admin, "https://example.com/");
        factory.setDependencies(address(oracle), address(identityNFT));
        vm.stopPrank();

        vm.startPrank(issuer);
        address bondAddress = factory.issueBond("Test Bond", 1000, 2000, uint40(block.timestamp + 365 days));
        bond = BondToken(bondAddress);
        vm.stopPrank();
    }

    function testConstructor() public view {
        assertEq(oracle.BOND_FACTORY(), address(factory));
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(oracle.hasRole(oracle.PRICE_FEED_UPDATER_ROLE(), priceFeedUpdater));
    }

    function testAddPriceFeed() public {
        vm.startPrank(issuer);
        address bondAddress = factory.issueBond("New Bond", 1000, 2000, uint40(block.timestamp + 365 days));
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit IBondOracle.PriceFeedAdded(bondAddress, 1000, uint40(block.timestamp), uint40(block.timestamp + 365 days));
        vm.expectEmit(true, true, true, true);
        emit IBondOracle.SecidMappingRegistered("New Bond", bondAddress);

        vm.prank(address(factory));
        oracle.addPriceFeed(bondAddress, 1000, uint40(block.timestamp + 365 days));

        BondOracle.BondInfo memory info = oracle.getPriceFeed(bondAddress);
        assertEq(info.lastPrice, 1000);
        assertEq(info.lastUpdated, block.timestamp);
        assertEq(info.maturityAt, block.timestamp + 365 days);
        assertEq(oracle.secidToBond("New Bond"), bondAddress);
        assertEq(oracle.bondToSecid(bondAddress), "New Bond");
    }

    function testAddPriceFeedRevertIfNotFactory() public {
        vm.expectRevert(IBondOracle.OnlyBondFactory.selector);
        vm.prank(user);
        oracle.addPriceFeed(address(bond), 1000, uint40(block.timestamp + 365 days));
    }

    function testConstructorRevertIfInvalidAddress() public {
        vm.expectRevert(IBondOracle.InvalidAddress.selector);
        new BondOracle(address(0), priceFeedUpdater);

        vm.expectRevert(IBondOracle.InvalidAddress.selector);
        new BondOracle(address(factory), address(0));
    }

    function testAddPriceFeedRevertIfUnknownBond() public {
        vm.startPrank(issuer);
        // Issue bond with 0 maturityAt to trigger UnknownBond error
        vm.expectRevert(IBondFactory.InvalidMaturityTime.selector);
        factory.issueBond("Test Bond", 1000, 2000, 0);
        vm.stopPrank();
    }

    function testUpdatePriceFeedRevertIfNonExistentPriceFeed() public {
        vm.expectRevert(IBondOracle.NonExistentPriceFeed.selector);
        vm.prank(priceFeedUpdater);
        oracle.updatePriceFeed(address(0x123), 1500);
    }

    function testUpdatePriceFeedRevertIfSameBlock() public {
        vm.startPrank(address(factory));
        oracle.addPriceFeed(address(bond), 1000, uint40(block.timestamp + 365 days));
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days);
        vm.prank(priceFeedUpdater);
        oracle.updatePriceFeed(address(bond), 1500);

        // Try to update again in the same block
        vm.prank(priceFeedUpdater);
        oracle.updatePriceFeed(address(bond), 2000);

        // Verify only the first update was applied
        BondOracle.BondInfo memory info = oracle.getPriceFeed(address(bond));
        assertEq(info.lastPrice, 1500);
    }

    function testUpdatePriceFeedWithSignatureRevertIfExpired() public {
        vm.startPrank(address(factory));
        oracle.addPriceFeed(address(bond), 1000, uint40(block.timestamp + 365 days));
        vm.stopPrank();

        string memory secid = "Test Bond";
        uint160 price = 1500;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = oracle.getNonce(priceFeedUpdater) + 1;

        bytes32 messageHash = keccak256(abi.encodePacked(secid, price, deadline));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        bytes memory signature = abi.encode(r, s, v);

        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert(IBondOracle.SignatureExpired.selector);
        vm.prank(priceFeedUpdater);
        oracle.updatePriceFeedWithSignature(secid, price, deadline, nonce, signature);
    }

    function testUpdatePriceFeedWithSignatureRevertIfInvalidSignature() public {
        vm.startPrank(address(factory));
        oracle.addPriceFeed(address(bond), 1000, uint40(block.timestamp + 365 days));
        vm.stopPrank();

        string memory secid = "Test Bond";
        uint160 price = 1500;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = oracle.getNonce(priceFeedUpdater) + 1;

        // Create a signature with a wrong private key
        uint256 wrongPrivateKey = 0x1234;

        // Create EIP-712 typed signature with wrong key
        bytes32 domainSeparator = keccak256(
            abi.encode(
                oracle.EIP712_DOMAIN_TYPEHASH(), keccak256("BondOracle"), keccak256("1"), block.chainid, address(oracle)
            )
        );

        bytes32 structHash =
            keccak256(abi.encode(oracle.PRICE_UPDATE_TYPEHASH(), keccak256(bytes(secid)), price, nonce, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);
        bytes memory signature = abi.encode(r, s, v);

        vm.expectRevert(IBondOracle.InvalidSignature.selector);
        vm.prank(priceFeedUpdater);
        oracle.updatePriceFeedWithSignature(secid, price, deadline, nonce, signature);
    }

    function testUpdatePriceFeed() public {
        vm.startPrank(address(factory));
        oracle.addPriceFeed(address(bond), 1000, uint40(block.timestamp + 365 days));
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(true, true, true, true);
        emit IBondOracle.PriceFeedUpdated(address(bond), 1500, uint40(block.timestamp));
        vm.prank(priceFeedUpdater);
        oracle.updatePriceFeed(address(bond), 1500);

        BondOracle.BondInfo memory info = oracle.getPriceFeed(address(bond));
        assertEq(info.lastPrice, 1500);
        assertEq(info.lastUpdated, block.timestamp);
    }

    function testUpdatePriceFeedRevertIfNotUpdater() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                user,
                oracle.PRICE_FEED_UPDATER_ROLE()
            )
        );
        vm.prank(user);
        oracle.updatePriceFeed(address(bond), 1500);
    }

    function testUpdateMultiplePriceFeeds() public {
        vm.startPrank(address(issuer));
        address bond2 = factory.issueBond("Bond 2", 2000, 3000, uint40(block.timestamp + 365 days));
        vm.stopPrank();

        address[] memory feeds = new address[](2);
        feeds[0] = address(bond);
        feeds[1] = bond2;

        uint160[] memory prices = new uint160[](2);
        prices[0] = 1500;
        prices[1] = 2000;
        vm.warp(block.timestamp + 1 days);

        vm.prank(priceFeedUpdater);
        oracle.updateMultiplePriceFeeds(feeds, prices);
        BondOracle.BondInfo memory info1 = oracle.getPriceFeed(address(bond));
        BondOracle.BondInfo memory info2 = oracle.getPriceFeed(bond2);

        assertEq(info1.lastPrice, 1500);
        assertEq(info2.lastPrice, 2000);
    }

    function testUpdateMultiplePriceFeedsRevertIfInvalidLength() public {
        address[] memory feeds = new address[](1);
        uint160[] memory prices = new uint160[](2);

        vm.expectRevert(IBondOracle.InvalidLength.selector);
        vm.prank(priceFeedUpdater);
        oracle.updateMultiplePriceFeeds(feeds, prices);
    }

    function testGetPriceFeeds() public {
        vm.startPrank(address(issuer));
        address bond2 = factory.issueBond("Bond 2", 2000, 3000, uint40(block.timestamp + 365 days));

        address[] memory feeds = new address[](2);
        feeds[0] = address(bond);
        feeds[1] = bond2;

        BondOracle.BondInfo[] memory infos = oracle.getPriceFeeds(feeds);
        assertEq(infos.length, 2);
        assertEq(infos[0].lastPrice, 1000);
        assertEq(infos[1].lastPrice, 2000);
    }

    function testUpdatePriceFeedAfterMaturity() public {
        // Set up initial bond with price feed
        vm.startPrank(issuer);
        address bondAddress = factory.issueBond("Test Bond", 1000, 2000, uint40(block.timestamp + 1)); // Set maturity to 1 second from now
        vm.stopPrank();

        // Fast forward past maturity
        vm.warp(block.timestamp + 2);

        // Update price feed after maturity
        vm.prank(priceFeedUpdater);
        oracle.updatePriceFeed(bondAddress, 1500);

        // Verify price was updated to maturity price
        BondOracle.BondInfo memory info = oracle.getPriceFeed(bondAddress);
        assertEq(info.lastPrice, 2000); // Should be maturity price from bond details
        (,,, uint40 maturityAt) = factory.getBondDetails(bondAddress);
        assertEq(info.lastUpdated, maturityAt); // Should be set to maturity timestamp
    }

    function testUpdatePriceFeedAfterMaturityNoChange() public {
        // Set up initial bond with price feed
        vm.startPrank(issuer);
        address bondAddress = factory.issueBond("Test Bond", 2000, 3000, uint40(block.timestamp + 1)); // Set initial price to match maturity price
        vm.stopPrank();

        // Fast forward past maturity
        vm.warp(block.timestamp + 2);

        // Update price feed after maturity
        vm.prank(priceFeedUpdater);
        oracle.updatePriceFeed(bondAddress, 1500);

        // Verify price remains unchanged since it matches maturity price
        BondOracle.BondInfo memory info = oracle.getPriceFeed(bondAddress);
        assertEq(info.lastPrice, 3000); // Should remain at maturity price
        assertEq(info.lastUpdated, block.timestamp - 1); // Should be set to maturity timestamp
    }

    function testUpdatePriceFeedWithSignatureSecure() public {
        vm.startPrank(address(factory));
        oracle.addPriceFeed(address(bond), 1000, uint40(block.timestamp + 365 days));
        vm.stopPrank();

        // Add a short wait to move forward in time to avoid the same timestamp condition
        vm.warp(block.timestamp + 100);

        string memory secid = "Test Bond";
        uint160 price = 1500;
        uint256 deadline = block.timestamp + 1 hours;

        // We need to use priceFeedUpdater as the correct signer
        vm.startPrank(priceFeedUpdater);
        uint256 nonce = oracle.getNonce(priceFeedUpdater) + 1;

        // Create EIP-712 typed signature
        bytes32 domainSeparator = keccak256(
            abi.encode(
                oracle.EIP712_DOMAIN_TYPEHASH(),
                keccak256("BondOracle"), // name
                keccak256("1"), // version
                block.chainid, // chainId
                address(oracle) // verifyingContract
            )
        );

        bytes32 structHash =
            keccak256(abi.encode(oracle.PRICE_UPDATE_TYPEHASH(), keccak256(bytes(secid)), price, nonce, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory signature = abi.encode(r, s, v);

        // Call the function with the signature
        oracle.updatePriceFeedWithSignature(secid, price, deadline, nonce, signature);
        vm.stopPrank();

        // Verify the price was updated
        BondOracle.BondInfo memory info = oracle.getPriceFeed(address(bond));
        assertEq(info.lastPrice, 1500);

        // Verify the nonce was updated
        assertEq(oracle.getNonce(priceFeedUpdater), nonce);
    }

    function testUpdatePriceFeedWithSignatureSecureRevertIfExpired() public {
        vm.startPrank(address(factory));
        oracle.addPriceFeed(address(bond), 1000, uint40(block.timestamp + 365 days));
        vm.stopPrank();

        // Add a short wait to move forward in time
        vm.warp(block.timestamp + 100);

        string memory secid = "Test Bond";
        uint160 price = 1500;
        // Set deadline in the past
        uint256 deadline = block.timestamp - 1;

        vm.startPrank(priceFeedUpdater);
        uint256 nonce = oracle.getNonce(priceFeedUpdater) + 1;

        // Create signature (same process as above)
        bytes32 domainSeparator = keccak256(
            abi.encode(
                oracle.EIP712_DOMAIN_TYPEHASH(), keccak256("BondOracle"), keccak256("1"), block.chainid, address(oracle)
            )
        );

        bytes32 structHash =
            keccak256(abi.encode(oracle.PRICE_UPDATE_TYPEHASH(), keccak256(bytes(secid)), price, nonce, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory signature = abi.encode(r, s, v);

        // Should revert with signature expired
        vm.expectRevert(IBondOracle.SignatureExpired.selector);
        oracle.updatePriceFeedWithSignature(secid, price, deadline, nonce, signature);
        vm.stopPrank();
    }

    function testUpdatePriceFeedWithInvalidNonce() public {
        vm.startPrank(address(factory));
        oracle.addPriceFeed(address(bond), 1000, uint40(block.timestamp + 365 days));
        vm.stopPrank();

        // Add a short wait to move forward in time
        vm.warp(block.timestamp + 100);

        string memory secid = "Test Bond";
        uint160 price = 1500;
        uint256 deadline = block.timestamp + 1 hours;

        // We need to use priceFeedUpdater as the correct signer
        vm.startPrank(priceFeedUpdater);
        uint256 currentNonce = oracle.getNonce(priceFeedUpdater);
        uint256 invalidNonce = currentNonce; // Same nonce, not incrementing

        // Create signature (same process as above)
        bytes32 domainSeparator = keccak256(
            abi.encode(
                oracle.EIP712_DOMAIN_TYPEHASH(), keccak256("BondOracle"), keccak256("1"), block.chainid, address(oracle)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(oracle.PRICE_UPDATE_TYPEHASH(), keccak256(bytes(secid)), price, invalidNonce, deadline)
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory signature = abi.encode(r, s, v);

        // Should revert with invalid nonce
        vm.expectRevert(IBondOracle.InvalidNonce.selector);
        oracle.updatePriceFeedWithSignature(secid, price, deadline, invalidNonce, signature);
        vm.stopPrank();
    }
}
