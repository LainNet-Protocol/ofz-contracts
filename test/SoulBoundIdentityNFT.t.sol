// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SoulBoundIdentityNFT} from "../src/SoulBoundIdentityNFT.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SoulBoundIdentityNFTTest is Test {
    SoulBoundIdentityNFT nft;
    address minter;
    address user;
    address subAccount;
    string baseURI;

    function setUp() public {
        minter = makeAddr("minter");
        user = makeAddr("user");
        subAccount = makeAddr("subAccount");
        baseURI = "https://example.com/";

        nft = new SoulBoundIdentityNFT(minter, baseURI);
    }

    function testFuzz_MintWithDifferentExpirations(uint40 expiration) public {
        vm.assume(expiration > 0 && expiration < 10000 days); // Reasonable bounds

        vm.prank(minter);
        nft.mint(user, expiration);

        (bool isWhitelisted,,) = nft.isWhitelisted(user);
        assertTrue(isWhitelisted);

        // Check just before expiration
        vm.warp(block.timestamp + expiration - 1);
        (isWhitelisted,,) = nft.isWhitelisted(user);
        assertTrue(isWhitelisted);

        // Check after expiration
        vm.warp(block.timestamp + 2);
        (isWhitelisted,,) = nft.isWhitelisted(user);
        assertFalse(isWhitelisted);
    }

    function testFuzz_AddMultipleSubAccounts(uint8 numAccounts) public {
        vm.assume(numAccounts > 0 && numAccounts <= 16);

        vm.prank(minter);
        nft.mint(user, 365 days);

        vm.startPrank(user);
        for (uint8 i = 0; i < numAccounts; i++) {
            address newSubAccount = makeAddr(string(abi.encodePacked("sub", vm.toString(i))));
            nft.addSubAccount(newSubAccount);

            (bool isWhitelisted, address mainAccount,) = nft.isWhitelisted(newSubAccount);
            assertTrue(isWhitelisted);
            assertEq(mainAccount, user);
        }
        vm.stopPrank();

        address[] memory subAccounts = nft.getSubAccounts(user);
        assertEq(subAccounts.length, numAccounts);
    }

    function testFuzz_TokenURIWithDifferentAddresses(address someUser) public {
        vm.assume(someUser != address(0));

        vm.prank(minter);
        nft.mint(someUser, 365 days);

        string memory expectedURI = string(abi.encodePacked(baseURI, Strings.toHexString(uint160(someUser), 20)));
        assertEq(nft.tokenURI(1), expectedURI);
    }

    function testMint() public {
        vm.prank(minter);
        nft.mint(user, 365 days);

        assertEq(nft.balanceOf(user), 1);
        assertEq(nft.ownerOf(1), user);

        (bool isWhitelisted, address mainAccount,) = nft.isWhitelisted(user);
        assertTrue(isWhitelisted);
        assertEq(mainAccount, user);
    }

    function testMintExpiration() public {
        vm.prank(minter);
        nft.mint(user, 30 days);

        // Check initially valid
        (bool isWhitelisted,,) = nft.isWhitelisted(user);
        assertTrue(isWhitelisted);

        // Skip to just before expiration
        vm.warp(block.timestamp + 29 days);
        (isWhitelisted,,) = nft.isWhitelisted(user);
        assertTrue(isWhitelisted);

        // Skip past expiration
        vm.warp(block.timestamp + 2 days);
        (isWhitelisted,,) = nft.isWhitelisted(user);
        assertFalse(isWhitelisted);
    }

    function testCannotMintTwice() public {
        vm.prank(minter);
        nft.mint(user, 365 days);

        vm.prank(minter);
        vm.expectRevert(SoulBoundIdentityNFT.IdentityAlreadyAssigned.selector);
        nft.mint(user, 365 days);
    }

    function testRevoke() public {
        vm.prank(minter);
        nft.mint(user, 365 days);

        vm.prank(minter);
        nft.revoke(user);

        assertEq(nft.balanceOf(user), 0);
        (bool isWhitelisted,,) = nft.isWhitelisted(user);
        assertFalse(isWhitelisted);
    }

    function testCannotRevokeNonExistentIdentity() public {
        vm.prank(minter);
        vm.expectRevert(SoulBoundIdentityNFT.IdentityNotFound.selector);
        nft.revoke(user);
    }

    function testAddSubAccount() public {
        vm.prank(minter);
        nft.mint(user, 365 days);

        vm.prank(user);
        nft.addSubAccount(subAccount);

        (bool isWhitelisted, address mainAccount,) = nft.isWhitelisted(subAccount);
        assertTrue(isWhitelisted);
        assertEq(mainAccount, user);

        address[] memory subAccounts = nft.getSubAccounts(user);
        assertEq(subAccounts.length, 1);
        assertEq(subAccounts[0], subAccount);
    }

    function testSubAccountWithExpiredMain() public {
        vm.prank(minter);
        nft.mint(user, 30 days);

        vm.prank(user);
        nft.addSubAccount(subAccount);

        // Initially both should be whitelisted
        (bool isWhitelisted,,) = nft.isWhitelisted(user);
        assertTrue(isWhitelisted);
        (isWhitelisted,,) = nft.isWhitelisted(subAccount);
        assertTrue(isWhitelisted);

        // Skip past expiration
        vm.warp(block.timestamp + 31 days);

        // Both should now be non-whitelisted
        (isWhitelisted,,) = nft.isWhitelisted(user);
        assertFalse(isWhitelisted);
        (isWhitelisted,,) = nft.isWhitelisted(subAccount);
        assertFalse(isWhitelisted);
    }

    function testCannotAddSubAccountWhenExpired() public {
        vm.prank(minter);
        nft.mint(user, 1 days);

        vm.warp(block.timestamp + 2 days);

        vm.prank(user);
        vm.expectRevert(SoulBoundIdentityNFT.IdentityExpired.selector);
        nft.addSubAccount(subAccount);
    }

    function testRemoveSubAccount() public {
        vm.prank(minter);
        nft.mint(user, 365 days);

        vm.prank(user);
        nft.addSubAccount(subAccount);

        vm.prank(user);
        nft.removeSubAccount(subAccount);

        (bool isWhitelisted,,) = nft.isWhitelisted(subAccount);
        assertFalse(isWhitelisted);

        address[] memory subAccounts = nft.getSubAccounts(user);
        assertEq(subAccounts.length, 0);
    }

    function testCannotTransfer() public {
        vm.prank(minter);
        nft.mint(user, 365 days);

        vm.prank(user);
        vm.expectRevert(SoulBoundIdentityNFT.TransferDisabled.selector);
        nft.transferFrom(user, address(0x4), 0);
    }

    function testCannotSafeTransfer() public {
        vm.prank(minter);
        nft.mint(user, 365 days);

        vm.startPrank(user);
        vm.expectRevert(SoulBoundIdentityNFT.TransferDisabled.selector);
        nft.safeTransferFrom(user, address(0x4), 0);

        vm.expectRevert(SoulBoundIdentityNFT.TransferDisabled.selector);
        nft.safeTransferFrom(user, address(0x4), 0, "");
        vm.stopPrank();
    }

    function testCannotApprove() public {
        vm.prank(minter);
        nft.mint(user, 365 days);

        vm.startPrank(user);
        vm.expectRevert(SoulBoundIdentityNFT.ApprovalDisabled.selector);
        nft.approve(address(0x4), 0);

        vm.expectRevert(SoulBoundIdentityNFT.ApprovalDisabled.selector);
        nft.setApprovalForAll(address(0x4), true);

        vm.expectRevert(SoulBoundIdentityNFT.ApprovalDisabled.selector);
        nft.getApproved(0);

        assertFalse(nft.isApprovedForAll(user, address(0x4)));
        vm.stopPrank();
    }

    function testTokenURI() public {
        vm.prank(minter);
        nft.mint(user, 365 days);

        string memory expectedURI = string(abi.encodePacked(baseURI, Strings.toHexString(uint160(user), 20)));
        assertEq(nft.tokenURI(1), expectedURI);
    }

    function testMaxSubAccounts() public {
        vm.prank(minter);
        nft.mint(user, 365 days);

        vm.startPrank(user);
        for (uint8 i = 1; i <= 16; i++) {
            address newSubAccount = makeAddr(string(abi.encodePacked("sub", vm.toString(i))));
            nft.addSubAccount(newSubAccount);
        }

        address oneMoreAccount = makeAddr("oneMore");
        vm.expectRevert(SoulBoundIdentityNFT.MaxSubAccountsReached.selector);
        nft.addSubAccount(oneMoreAccount);
        vm.stopPrank();
    }

    function testGetSubAccounts() public {
        vm.prank(minter);
        nft.mint(user, 365 days);

        vm.startPrank(user);
        address sub1 = makeAddr("sub1");
        address sub2 = makeAddr("sub2");
        nft.addSubAccount(sub1);
        nft.addSubAccount(sub2);

        address[] memory subAccounts = nft.getSubAccounts();
        assertEq(subAccounts.length, 2);
        assertEq(subAccounts[0], sub1);
        assertEq(subAccounts[1], sub2);
        vm.stopPrank();
    }

    function testCannotInitializeWithZeroAddress() public {
        vm.expectRevert(SoulBoundIdentityNFT.InvalidAddress.selector);
        new SoulBoundIdentityNFT(address(0), baseURI);
    }

    function testSupportsInterface() public view {
        // Test ERC721 interface support
        bytes4 erc721InterfaceId = type(IERC721).interfaceId;
        assertTrue(nft.supportsInterface(erc721InterfaceId));

        // Test AccessControl interface support
        bytes4 accessControlInterfaceId = type(IAccessControl).interfaceId;
        assertTrue(nft.supportsInterface(accessControlInterfaceId));

        // Test non-supported interface
        bytes4 randomInterfaceId = bytes4(keccak256("random()"));
        assertFalse(nft.supportsInterface(randomInterfaceId));
    }
}
