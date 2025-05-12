// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {BondToken} from "../src/BondToken.sol";
import {BondFactory} from "../src/BondFactory.sol";
import {BondOracle} from "../src/BondOracle.sol";
import {SoulBoundIdentityNFT} from "../src/SoulBoundIdentityNFT.sol";

error NotBondIssuer();
error NotWhitelisted();
error InsufficientBalanceForRedeem();

contract BondTokenTest is Test {
    BondToken public bond;
    BondFactory public factory;
    BondOracle public oracle;
    SoulBoundIdentityNFT public identityNFT;
    address public issuer;
    address public admin;
    address public user;
    address public minter;
    string public baseURI;

    event RedeemRequested(address indexed user, uint256 amount);

    function setUp() public {
        minter = makeAddr("minter");
        baseURI = "https://example.com/";
        identityNFT = new SoulBoundIdentityNFT(minter, baseURI);

        admin = makeAddr("admin");
        issuer = makeAddr("issuer");
        user = makeAddr("user");

        vm.startPrank(admin);
        factory = new BondFactory(issuer);
        oracle = new BondOracle(address(factory), admin);
        factory.setDependencies(address(oracle), address(identityNFT));
        vm.stopPrank();
        vm.startPrank(issuer);
        address bondAddress = factory.issueBond("Test Bond", 1000, 2000, uint40(block.timestamp + 365 days));
        bond = BondToken(bondAddress);
        vm.stopPrank();
    }

    function testConstructor() public view {
        assertEq(bond.maturityPrice(), 2000);
        assertEq(bond.maturityAt(), block.timestamp + 365 days);
        assertEq(bond.BOND_FACTORY(), address(factory));
        assertEq(bond.IDENTITY_NFT(), address(identityNFT));
    }

    function testDecimals() public view {
        assertEq(bond.decimals(), 0);
    }

    function testMint() public {
        vm.startPrank(minter);
        identityNFT.mint(user, 365 days);
        vm.stopPrank();

        vm.startPrank(issuer);
        bond.mint(user, 1000);
        assertEq(bond.balanceOf(user), 1000);
        vm.stopPrank();
    }

    function testMintRevertIfNotIssuer() public {
        vm.expectRevert(NotBondIssuer.selector);
        vm.prank(user);
        bond.mint(user, 1000);
    }

    function testMintRevertIfNotWhitelisted() public {
        vm.startPrank(issuer);
        vm.expectRevert(NotWhitelisted.selector);
        bond.mint(user, 1000);
        vm.stopPrank();
    }

    function testRequestRedeem() public {
        vm.startPrank(minter);
        identityNFT.mint(user, 365 days);
        vm.stopPrank();

        vm.startPrank(issuer);
        bond.mint(user, 1000);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectEmit(true, false, false, true);
        emit RedeemRequested(user, 500);
        bond.requestRedeem(500);
        vm.stopPrank();
    }

    function testRequestRedeemRevertIfNotWhitelisted() public {
        vm.expectRevert(NotWhitelisted.selector);
        vm.prank(user);
        bond.requestRedeem(500);
    }

    function testRequestRedeemRevertIfInsufficientBalance() public {
        vm.startPrank(minter);
        identityNFT.mint(user, 365 days);
        vm.stopPrank();

        vm.startPrank(issuer);
        bond.mint(user, 1000);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(InsufficientBalanceForRedeem.selector);
        bond.requestRedeem(1500);
        vm.stopPrank();
    }

    function testFinalizeRedeem() public {
        vm.startPrank(minter);
        identityNFT.mint(user, 365 days);
        vm.stopPrank();

        vm.startPrank(issuer);
        bond.mint(user, 1000);
        vm.stopPrank();
        console.log(factory.hasRole(factory.BOND_ISSUER_ROLE(), issuer));
        vm.startPrank(issuer);
        bond.finalizeRedeem(user, 500);
        assertEq(bond.balanceOf(user), 500);
        vm.stopPrank();
    }

    function testFinalizeRedeemRevertIfNotIssuer() public {
        vm.expectRevert(NotBondIssuer.selector);
        vm.prank(user);
        bond.finalizeRedeem(user, 500);
    }

    function testTransfer() public {
        vm.startPrank(minter);
        identityNFT.mint(user, 365 days);
        identityNFT.mint(admin, 365 days);
        vm.stopPrank();

        vm.startPrank(issuer);
        bond.mint(user, 1000);
        vm.stopPrank();

        vm.startPrank(user);
        bond.transfer(admin, 500);
        assertEq(bond.balanceOf(user), 500);
        assertEq(bond.balanceOf(admin), 500);
        vm.stopPrank();
    }

    function testTransferRevertIfNotWhitelisted() public {
        vm.startPrank(minter);
        identityNFT.mint(user, 365 days);
        vm.stopPrank();

        vm.startPrank(issuer);
        bond.mint(user, 1000);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(NotWhitelisted.selector);
        bond.transfer(admin, 500);
        vm.stopPrank();
    }

    function testTransferRevertIfZeroAddress() public {
        vm.startPrank(minter);
        identityNFT.mint(user, 365 days);
        vm.stopPrank();

        vm.startPrank(issuer);
        bond.mint(user, 1000);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        bond.transfer(address(0), 500);
        vm.stopPrank();
    }
}
