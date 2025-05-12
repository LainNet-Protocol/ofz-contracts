// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./interfaces/ISoulBoundIdentityNFT.sol";

contract SoulBoundIdentityNFT is ISoulBoundIdentityNFT, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct IdentityInfo {
        uint256 tokenId;
        uint40 expiration;
        EnumerableSet.AddressSet subAccounts;
    }

    // Mapping from token owner to their identity info
    mapping(address => IdentityInfo) private _identityInfo;

    // Mapping to track which main account a sub account belongs to
    mapping(address => address) private _subAccountToOwner;

    // Mapping from token id to token owner
    mapping(uint256 => address) private _tokenOwner;

    error MaxSubAccountsReached();
    error NotTokenOwner();
    error SubAccountNotFound();
    error SubAccountAlreadyExists();
    error SubAccountAlreadyTiedToOwner();

    error TransferDisabled();
    error ApprovalDisabled();

    error IdentityExpired();
    error InvalidAddress();
    error IdentityAlreadyAssigned();
    error IdentityNotFound();

    modifier onlyValidIdentityHolder() {
        IdentityInfo storage info = _identityInfo[msg.sender];
        if (info.expiration == 0) revert NotTokenOwner();
        if (info.expiration < block.timestamp) revert IdentityExpired();
        _;
    }

    uint256 internal _nextTokenId;
    uint8 constant MAX_SUB_ACCOUNTS = 16;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    string internal BASE_URI;

    constructor(address _initialMinter, string memory _baseURI) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        BASE_URI = _baseURI;

        if (_initialMinter == address(0)) {
            revert InvalidAddress();
        }

        _grantRole(MINTER_ROLE, _initialMinter);

        _nextTokenId = 1;
    }

    function mint(address to, uint40 expiration) external onlyRole(MINTER_ROLE) {
        if (_identityInfo[to].expiration > 0) {
            revert IdentityAlreadyAssigned();
        }

        uint256 tokenId = _nextTokenId++;

        _identityInfo[to].expiration = uint40(block.timestamp) + expiration;
        _identityInfo[to].tokenId = tokenId;
        // We don't clear EnumberableSet because it might have sub accounts from previous identity

        _tokenOwner[tokenId] = to;

        // EIP721 treats transfer from address(0) as minting the token
        emit Transfer(address(0), to, tokenId);
    }

    function revoke(address to) external onlyRole(MINTER_ROLE) {
        IdentityInfo storage info = _identityInfo[to];
        if (info.expiration == 0) revert IdentityNotFound();

        // Get token ID before clearing identity info
        uint256 tokenId = info.tokenId;

        // Clear identity info
        info.expiration = 0;

        // Clear token ownership
        delete _tokenOwner[tokenId];

        // EIP721 treats transfer to address(0) as burning the token
        emit Transfer(to, address(0), tokenId);
    }

    function addSubAccount(address subAccount) external onlyValidIdentityHolder {
        IdentityInfo storage info = _identityInfo[msg.sender];

        if (subAccount == address(0) || subAccount == msg.sender) revert InvalidAddress();
        if (_subAccountToOwner[subAccount] != address(0)) revert SubAccountAlreadyTiedToOwner();

        if (info.subAccounts.length() >= MAX_SUB_ACCOUNTS) revert MaxSubAccountsReached();
        if (!info.subAccounts.add(subAccount)) revert SubAccountAlreadyExists();

        _subAccountToOwner[subAccount] = msg.sender;
        emit SubAccountAdded(msg.sender, subAccount);
    }

    function removeSubAccount(address subAccount) external onlyValidIdentityHolder {
        IdentityInfo storage info = _identityInfo[msg.sender];
        if (!info.subAccounts.remove(subAccount)) revert SubAccountNotFound();
        delete _subAccountToOwner[subAccount];

        emit SubAccountRemoved(msg.sender, subAccount);
    }

    function isWhitelisted(address account) external view returns (bool, address mainAccount, uint40 expiration) {
        expiration = _identityInfo[account].expiration;
        if (expiration != 0) {
            return (expiration > block.timestamp, account, expiration);
        }

        mainAccount = _subAccountToOwner[account];
        if (mainAccount != address(0)) {
            expiration = _identityInfo[mainAccount].expiration;
            return (expiration > block.timestamp, mainAccount, expiration);
        }

        return (false, address(0), expiration);
    }

    function getSubAccounts() external view returns (address[] memory) {
        return _getSubAccounts(msg.sender);
    }

    function getSubAccounts(address mainAccount) external view returns (address[] memory) {
        return _getSubAccounts(mainAccount);
    }

    function _getSubAccounts(address mainAccount) internal view returns (address[] memory) {
        return _identityInfo[mainAccount].subAccounts.values();
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _identityInfo[owner].expiration > 0 ? 1 : 0;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return _tokenOwner[tokenId];
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        address owner = _tokenOwner[tokenId];

        string memory hexAddr = Strings.toHexString(uint256(uint160(owner)), 20);
        return string(abi.encodePacked(BASE_URI, hexAddr));
    }

    function transferFrom(address, address, uint256) external pure override {
        revert TransferDisabled();
    }

    function safeTransferFrom(address, address, uint256) external pure override {
        revert TransferDisabled();
    }

    function safeTransferFrom(address, address, uint256, bytes memory) external pure override {
        revert TransferDisabled();
    }

    function approve(address, uint256) external pure override {
        revert ApprovalDisabled();
    }

    function setApprovalForAll(address, bool) external pure override {
        revert ApprovalDisabled();
    }

    function getApproved(uint256) external pure override returns (address) {
        revert ApprovalDisabled();
    }

    function isApprovedForAll(address, address) external pure override returns (bool) {
        return false;
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, IERC165) returns (bool) {
        return interfaceId == type(IERC721).interfaceId || AccessControl.supportsInterface(interfaceId);
    }
}
