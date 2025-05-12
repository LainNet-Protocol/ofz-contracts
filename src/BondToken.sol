// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/ISoulBoundIdentityNFT.sol";
import "./interfaces/IBondFactory.sol";
import "./interfaces/IBondToken.sol";

contract BondToken is ERC20, IBondToken {
    uint160 public immutable maturityPrice;
    uint40 public immutable maturityAt;

    address public immutable BOND_FACTORY;
    address public immutable IDENTITY_NFT;

    constructor(string memory name, string memory symbol, uint160 _maturityPrice, uint40 _maturityAt)
        ERC20(name, symbol)
    {
        maturityPrice = _maturityPrice;
        maturityAt = _maturityAt;
        BOND_FACTORY = msg.sender;
        IDENTITY_NFT = IBondFactory(msg.sender).IDENTITY_NFT();
    }

    modifier onlyBondIssuer() {
        if (!_hasBondIssuerRole(msg.sender)) {
            revert NotBondIssuer();
        }
        _;
    }

    modifier onlyKYC() {
        (bool whitelisted,,) = ISoulBoundIdentityNFT(IDENTITY_NFT).isWhitelisted(msg.sender);
        if (!whitelisted) {
            revert NotWhitelisted();
        }
        _;
    }

    function _hasBondIssuerRole(address user) internal view returns (bool) {
        return IBondFactory(BOND_FACTORY).hasRole(IBondFactory(BOND_FACTORY).BOND_ISSUER_ROLE(), user);
    }

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function requestRedeem(uint256 amount) external onlyKYC {
        if (amount > balanceOf(msg.sender)) {
            revert InsufficientBalanceForRedeem();
        }
        // This is just to track via offchain services, it's possible to spam the event, but it's not a big deal
        emit RedeemRequested(msg.sender, amount);
    }

    function mint(address to, uint256 amount) external onlyBondIssuer {
        // Won't allow to mint to non-whitelisted addresses due to the check in _update
        _mint(to, amount);
    }

    function finalizeRedeem(address user, uint256 amount) external onlyBondIssuer {
        // Internaly it will check if the user has enough balance
        // Off-chain we return user their balance
        _burn(user, amount);
    }

    function _update(address from, address to, uint256 amount) internal virtual override {
        // Skip for mint
        if (from != address(0)) {
            (bool whitelisted,,) = ISoulBoundIdentityNFT(IDENTITY_NFT).isWhitelisted(from);
            if (!whitelisted) revert NotWhitelisted();
        }

        // Skip for burn
        if (to != address(0)) {
            (bool whitelisted,,) = ISoulBoundIdentityNFT(IDENTITY_NFT).isWhitelisted(to);
            if (!whitelisted) revert NotWhitelisted();
        }

        super._update(from, to, amount);
    }
}
