// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/BondFactory.sol";
import "../src/BondOracle.sol";
import "../src/BondToken.sol";
import "../src/SoulBoundIdentityNFT.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract BondFactoryTest is Test {
    BondFactory public factory;
    BondOracle public oracle;
    SoulBoundIdentityNFT public identityNFT;
    address public issuer;
    address public admin;
    address public user;
    address public minter;
    address public subAccount;
    string public baseURI;

    event BondCreated(
        address indexed bond, string name, uint160 initialPrice, uint160 maturityPrice, uint40 maturityAt
    );
    event DependenciesSet(address indexed bondOracle, address indexed identityNFT);

    function setUp() public {
        minter = makeAddr("minter");
        subAccount = makeAddr("subAccount");
        baseURI = "https://example.com/";

        identityNFT = new SoulBoundIdentityNFT(minter, baseURI);

        admin = makeAddr("admin");
        issuer = makeAddr("issuer");
        user = makeAddr("user");

        vm.startPrank(admin);
        factory = new BondFactory(issuer);
        oracle = new BondOracle(address(factory), admin);
        vm.stopPrank();
    }

    function testConstructor() public view {
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(factory.hasRole(factory.BOND_ISSUER_ROLE(), issuer));
    }

    function testSetDependencies() public {
        vm.startPrank(admin);
        factory.setDependencies(address(oracle), address(identityNFT));
        assertEq(factory.BOND_ORACLE(), address(oracle));
        assertEq(factory.IDENTITY_NFT(), address(identityNFT));
        vm.stopPrank();
    }

    function testSetDependenciesRevertIfNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, factory.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        factory.setDependencies(address(oracle), address(identityNFT));
    }

    function testSetDependenciesRevertIfAlreadySet() public {
        vm.startPrank(admin);
        factory.setDependencies(address(oracle), address(identityNFT));
        vm.expectRevert(IBondFactory.DependenciesAlreadySet.selector);
        factory.setDependencies(address(oracle), address(identityNFT));
        vm.stopPrank();
    }

    function testSetDependenciesRevertIfZeroAddress() public {
        vm.startPrank(admin);

        // Test setting zero address for bond oracle
        vm.expectRevert(IBondFactory.InvalidAddress.selector);
        factory.setDependencies(address(0), address(identityNFT));

        // Test setting zero address for identity NFT
        vm.expectRevert(IBondFactory.InvalidAddress.selector);
        factory.setDependencies(address(oracle), address(0));

        // Test setting both addresses as zero
        vm.expectRevert(IBondFactory.InvalidAddress.selector);
        factory.setDependencies(address(0), address(0));

        vm.stopPrank();
    }

    function testConstructorRevertIfZeroAddress() public {
        vm.expectRevert(IBondFactory.InvalidAddress.selector);
        new BondFactory(address(0));
    }

    function testIssueBondRevertIfDependenciesNotSet() public {
        vm.startPrank(issuer);
        vm.expectRevert(IBondFactory.DependenciesNotSet.selector);
        factory.issueBond("Test Bond", 1000, 2000, uint40(block.timestamp + 365 days));
        vm.stopPrank();
    }

    function testIssueBond() public {
        vm.startPrank(admin);
        factory.setDependencies(address(oracle), address(identityNFT));
        vm.stopPrank();

        string memory name = "Test Bond";
        uint160 initialPrice = 1000;
        uint160 maturityPrice = 2000;
        uint40 maturityAt = uint40(block.timestamp + 365 days);

        vm.startPrank(issuer);
        vm.expectEmit(false, true, true, true);
        emit BondCreated(address(0), name, initialPrice, maturityPrice, maturityAt);
        address bondAddress = factory.issueBond(name, initialPrice, maturityPrice, maturityAt);
        vm.stopPrank();

        (string memory bondName, uint160 bondInitialPrice, uint160 bondMaturityPrice, uint40 bondMaturityAt) =
            factory.getBondDetails(bondAddress);

        assertEq(bondName, name);
        assertEq(bondInitialPrice, initialPrice);
        assertEq(bondMaturityPrice, maturityPrice);
        assertEq(bondMaturityAt, maturityAt);
    }

    function testIssueBondRevertIfDuplicateName() public {
        vm.startPrank(admin);
        factory.setDependencies(address(oracle), address(identityNFT));
        vm.stopPrank();

        string memory name = "Test Bond";
        uint160 initialPrice = 1000;
        uint160 maturityPrice = 2000;
        uint40 maturityAt = uint40(block.timestamp + 365 days);

        vm.startPrank(issuer);
        // First issuance should succeed
        factory.issueBond(name, initialPrice, maturityPrice, maturityAt);

        // Second issuance with same name should revert
        vm.expectRevert();
        factory.issueBond(name, initialPrice, maturityPrice, maturityAt);
        vm.stopPrank();
    }

    function testIssueBondRevertIfNotIssuer() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, factory.BOND_ISSUER_ROLE()
            )
        );
        vm.prank(user);
        factory.issueBond("Test Bond", 1000, 2000, uint40(block.timestamp + 365 days));
    }

    function testIssueBondRevertIfInvalidMaturityTime() public {
        vm.startPrank(admin);
        factory.setDependencies(address(oracle), address(identityNFT));
        vm.stopPrank();

        vm.startPrank(issuer);
        vm.expectRevert(IBondFactory.InvalidMaturityTime.selector);
        factory.issueBond("Test Bond", 1000, 2000, uint40(block.timestamp - 1));
        vm.stopPrank();
    }

    function testIssueBondRevertIfInvalidPrice() public {
        vm.startPrank(admin);
        factory.setDependencies(address(oracle), address(identityNFT));
        vm.stopPrank();

        vm.startPrank(issuer);
        vm.expectRevert(IBondFactory.InvalidPrice.selector);
        factory.issueBond("Test Bond", 0, 2000, uint40(block.timestamp + 365 days));
        vm.stopPrank();
    }

    function testIsBondIssuer() public view {
        assertTrue(factory.hasRole(factory.BOND_ISSUER_ROLE(), issuer));
        assertFalse(factory.hasRole(factory.BOND_ISSUER_ROLE(), user));
    }
}
