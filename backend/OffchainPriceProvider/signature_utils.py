import os
import time
from web3 import Web3
from config import Config
import eth_keys
from eth_keys import keys
import nonce_manager
from eth_abi.abi import encode

def load_private_key():
    """
    Load the private key using the Config class.
    
    Returns:
        str: Private key as a hex string (without 0x prefix)
    """
    return Config.get_private_key()

def create_signature(secid, price, nonce=None, deadline=None):
    """
    Create Ethereum signature for the given OFZ bond SECID and price using EIP-712.
    This matches the signature format expected by BondOracle.sol's updatePriceFeedWithSignature.
    
    Args:
        secid (str): SECID of the OFZ bond
        price (int): Price converted to uint160 format
        nonce (int, optional): Nonce to prevent replay attacks. If None, a timestamp-based nonce will be used.
        deadline (int, optional): Timestamp after which the signature is no longer valid. If None, default expiry time is used.
        
    Returns:
        tuple: (signature_hex, nonce, deadline) where:
               - signature_hex is the ABI-encoded signature string that can be decoded with abi.decode(_signature, (bytes32, bytes32, uint8))
               - nonce is the nonce used in the signature
               - deadline is the timestamp after which the signature is no longer valid
    """
    try:
        private_key_hex = load_private_key()
        web3 = Web3()
        
        # Generate nonce and deadline if not provided
        if nonce is None:
            # Use nonce manager to get the next sequential nonce
            nonce = nonce_manager.get_next_nonce()
            
        if deadline is None:
            # Default expiry is based on config
            deadline = int(time.time()) + Config.SIGNATURE_EXPIRY_SECONDS
            
        # This MUST match exactly how the contract calculates the domain separator
        # From BondOracle.sol constructor:
        # DOMAIN_SEPARATOR = keccak256(
        #     abi.encode(
        #         EIP712_DOMAIN_TYPEHASH,
        #         keccak256("BondOracle"), // name
        #         keccak256("1"), // version
        #         block.chainid, // chainId
        #         address(this) // verifyingContract
        #     )
        # );
            
        # Domain separator params
        chain_id = Config.CHAIN_ID
        verifying_contract = Config.BOND_ORACLE_ADDRESS
        
        # EIP-712 domain hash - MUST match contract's EIP712_DOMAIN_TYPEHASH
        domain_type_hash = web3.keccak(text="EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
        name_hash = web3.keccak(text="BondOracle")
        version_hash = web3.keccak(text="1")
        
        # Calculate domain separator exactly as the contract does
        encoded_domain = encode(
            ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
            [
                domain_type_hash,
                name_hash,
                version_hash,
                chain_id,
                Web3.to_checksum_address(verifying_contract)
            ]
        )
        domain_separator = web3.keccak(encoded_domain)
        
        # Must match contract's PRICE_UPDATE_TYPEHASH
        price_update_type_hash = web3.keccak(text="PriceUpdate(string secid,uint160 price,uint256 nonce,uint256 deadline)")
        
        # Important: In the contract, string hashing is done with keccak256(bytes(secid))
        secid_hash = web3.keccak(text=secid)
        
        # Encode the PriceUpdate struct exactly like the contract
        # In contract: keccak256(abi.encode(PRICE_UPDATE_TYPEHASH, keccak256(bytes(_secid)), _price, _nonce, _deadline))
        encoded_struct = encode(
            ['bytes32', 'bytes32', 'uint160', 'uint256', 'uint256'],
            [
                price_update_type_hash,
                secid_hash,
                price,
                nonce, 
                deadline
            ]
        )
        struct_hash = web3.keccak(encoded_struct)
        
        # Create the EIP-712 hash exactly as in contract's _hashTypedData method
        # keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash))
        message_hash = web3.keccak(
            b"\x19\x01" + domain_separator + struct_hash
        )
        
        # Sign the hash using eth_keys
        private_key = keys.PrivateKey(bytes.fromhex(private_key_hex))
        signature = private_key.sign_msg_hash(message_hash)
        
        # Extract the signature components
        r = signature.r
        s = signature.s
        v = signature.v
        
        # Debug output
        print(f"EIP-712 Message hash: {message_hash.hex()}")
        print(f"Signature components - r: {hex(r)}, s: {hex(s)}, v: {v}")
        
        # Format the signature for the contract (which expects standard Ethereum v value 27/28)
        # Ensure v is in the range [27, 28]
        if v < 27:
            v_adjusted = v + 27
        else:
            v_adjusted = v
            
        print(f"Adjusted v value: {v_adjusted}")
        
        # Convert to bytes for ABI encoding
        r_bytes = r.to_bytes(32, byteorder='big')
        s_bytes = s.to_bytes(32, byteorder='big')
        
        # Important: Use ABI encoding instead of simple concatenation
        # This matches how the contract decodes with abi.decode(_signature, (bytes32, bytes32, uint8))
        signature_bytes = encode(
            ['bytes32', 'bytes32', 'uint8'],
            [
                r_bytes,  # bytes32 r
                s_bytes,  # bytes32 s
                v_adjusted  # uint8 v
            ]
        )
        signature_hex = '0x' + signature_bytes.hex()
        
        # Verify the signature on our end
        # Recover the address from the signature
        public_key = keys.PrivateKey(bytes.fromhex(private_key_hex)).public_key
        signer_address = public_key.to_checksum_address()
        print(f"Generated signature for {secid} by {signer_address}")
        print(f"Signature (hex): {signature_hex}")
        print(f"Nonce: {nonce}, Deadline: {deadline}")
        
        return signature_hex, nonce, deadline
        
    except Exception as e:
        import traceback
        print(f"Error creating signature: {e}")
        print(traceback.format_exc())
        raise
    
def get_signer_address():
    """
    Get the Ethereum address corresponding to the private key
    
    Returns:
        str: Ethereum address
    """
    private_key_hex = load_private_key()
    private_key = keys.PrivateKey(bytes.fromhex(private_key_hex))
    public_key = private_key.public_key
    return public_key.to_checksum_address()
