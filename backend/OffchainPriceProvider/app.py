import os
import json
import time
import logging
from flask import Flask, jsonify, request
from flask_cors import CORS
from cache_manager import CacheManager
from signature_utils import create_signature, get_signer_address
from get_ofz_prices import fetch_ofz_list, market_prices, get_price, get_bond_details
from config import Config
from web3 import Web3

# Configure logging
logging.basicConfig(level=logging.INFO, 
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('ofz_oracle')

# Initialize Flask app
app = Flask(__name__)
CORS(app)  # Enable CORS for all routes
cache_manager = CacheManager(Config.CACHE_TTL)

# Initialize a cache for registered bonds (to avoid frequent blockchain queries)
registered_bonds_cache = {
    "timestamp": 0,
    "bonds": [],
    "ttl": Config.REGISTERED_BONDS_CACHE_TTL
}

def get_registered_bonds():
    """
    Get list of bond SECIDs that are registered on the blockchain.
    Uses caching to avoid frequent blockchain queries.
    
    Returns:
        list: A list of registered SECIDs
    """
    global registered_bonds_cache
    
    # Check if cache is still valid
    current_time = int(time.time())
    if current_time - registered_bonds_cache["timestamp"] < registered_bonds_cache["ttl"]:
        logger.info(f"Using cached registered bonds list ({len(registered_bonds_cache['bonds'])} bonds)")
        return registered_bonds_cache["bonds"]
    
    logger.info("Fetching registered bonds from blockchain")
    
    try:
        # Initialize Web3 connection
        w3 = Web3(Web3.HTTPProvider(Config.ETH_RPC_URL))
        if not w3.is_connected():
            logger.error("Failed to connect to Ethereum node")
            return []
        
        logger.info(f"Connected to Ethereum node. Chain ID: {w3.eth.chain_id}")
        
        # Load ABI for the BondOracle contract - assuming we have a simple ABI snippet for the required functions
        oracle_abi = [
            {
                "inputs": [{"internalType": "string", "name": "_secid", "type": "string"}],
                "name": "secidToBond",
                "outputs": [{"internalType": "address", "name": "", "type": "address"}],
                "stateMutability": "view",
                "type": "function"
            }
        ]
        
        # Create contract instance
        oracle_address = Web3.to_checksum_address(Config.BOND_ORACLE_ADDRESS)
        oracle_contract = w3.eth.contract(address=oracle_address, abi=oracle_abi)
        
        # Fetch the list of OFZ bonds
        ofz_list = fetch_ofz_list()
        candidate_secids = [row["SECID"] for _, row in ofz_list.iterrows()]
        logger.info(f"Found {len(candidate_secids)} candidate SECIDs to check in the oracle")
        
        # Check each candidate SECID to see if it's registered in the oracle
        registered_secids = []
        for secid in candidate_secids:
            try:
                bond_address = oracle_contract.functions.secidToBond(secid).call()
                if bond_address != "0x0000000000000000000000000000000000000000":
                    logger.debug(f"SECID {secid} is registered in the oracle with bond address {bond_address}")
                    registered_secids.append(secid)
            except Exception as e:
                logger.warning(f"Error checking SECID {secid}: {str(e)}")
                continue
        
        logger.info(f"Found {len(registered_secids)} registered SECIDs in the oracle")
        
        # Update cache
        registered_bonds_cache = {
            "timestamp": current_time,
            "bonds": registered_secids,
            "ttl": Config.REGISTERED_BONDS_CACHE_TTL
        }
        
        return registered_secids
    except Exception as e:
        logger.error(f"Error getting registered bonds: {str(e)}")
        return []

@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "ok", 
        "timestamp": int(time.time()),
        "signer_address": get_signer_address(),
        "cache_ttl": Config.CACHE_TTL
    })

@app.route('/api/prices', methods=['GET'])
def get_all_prices():
    # Check if signature is requested
    with_signature = request.args.get('sign') is not None
    
    # Try to get data from cache first
    cached_data = cache_manager.get_cached_data()
    if cached_data:
        # If signature is not requested but cache has it, we need to remove signatures from response
        if not with_signature and cached_data.get("prices"):
            # Create a new copy without signatures
            filtered_data = {
                "timestamp": cached_data["timestamp"],
                "prices": {}
            }
            
            for secid, price_info in cached_data["prices"].items():
                # Create a copy without signature
                price_copy = {k: v for k, v in price_info.items() if k != 'signature'}
                filtered_data["prices"][secid] = price_copy
            
            return jsonify(filtered_data)
        return jsonify(cached_data)
    
    # Cache miss, fetch fresh data
    try:
        ofz_list = fetch_ofz_list()
        price_data = {"timestamp": int(time.time()), "prices": {}}
        
        for index, row in ofz_list.iterrows():
            secid = row["SECID"]
            # Get price from MOEX (with fallback to candle data)
            price, is_current = get_price(secid)
            
            if price:
                # Convert price to uint160 format using the scaling factor
                # First multiply by 100, round, convert to int, then multiply by remaining scaling factor
                price_uint = int(round(float(price) * 100)) * (Config.PRICE_SCALING_FACTOR // 100)
                
                # Prepare price data
                price_info = {
                    "price": float(price),
                    "price_uint": price_uint,
                    "is_current_market_data": is_current,
                    "data_source": "market_price" if is_current else "daily_candle"
                }
                
                # Add signature only if requested
                if with_signature:
                    signature, nonce, deadline = create_signature(secid, price_uint)
                    price_info["signature"] = signature
                    price_info["nonce"] = nonce
                    price_info["deadline"] = deadline
                
                price_data["prices"][secid] = price_info
        
        # Store in cache
        cache_manager.cache_data(price_data)
        
        return jsonify(price_data)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/prices/<secid>', methods=['GET'])
def get_price_for_secid(secid):
    # Check if signature is requested
    with_signature = request.args.get('sign') is not None
    
    # Try to get data from cache first
    cached_data = cache_manager.get_cached_data()
    
    if cached_data and secid in cached_data.get("prices", {}):
        price_info = cached_data["prices"][secid]
        
        # If signature is not requested but cache has it, remove signature
        if not with_signature and "signature" in price_info:
            # Create a copy without signature
            price_info = {k: v for k, v in price_info.items() if k != 'signature'}
        
        return jsonify({
            "timestamp": cached_data["timestamp"],
            "price": price_info
        })
    
    # Cache miss or secid not in cache, fetch fresh data
    try:
        # Get price from MOEX (with fallback to candle data)
        price, is_current = get_price(secid)
        
        if price:
            # Convert price to uint160 format using the scaling factor
            # First multiply by 1000, round, convert to int, then multiply by remaining scaling factor
            price_uint = int(round(float(price) * 1000)) * (Config.PRICE_SCALING_FACTOR // 1000)
            
            # Prepare price data
            price_info = {
                "price": float(price),
                "price_uint": price_uint,
                "is_current_market_data": is_current,
                "data_source": "market_price" if is_current else "daily_candle"
            }
            
            # Add signature only if requested
            if with_signature:
                signature, nonce, deadline = create_signature(secid, price_uint)
                price_info["signature"] = signature
                price_info["nonce"] = nonce
                price_info["deadline"] = deadline
            
            price_data = {
                "timestamp": int(time.time()),
                "price": price_info
            }
            
            return jsonify(price_data)
        else:
            return jsonify({"error": f"No price data available for {secid} (checked both market data and recent candles)"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/bonds', methods=['GET'])
def get_all_bonds():
    """
    Endpoint to get a list of all available OFZ bonds.
    
    Query Parameters:
        onchain (bool): If 'true', returns only bonds that exist on the blockchain
    """
    try:
        # Check if onchain filter is requested
        onchain_only = request.args.get('onchain', '').lower() == 'true'
        
        # Fetch the list of OFZ bonds
        ofz_list = fetch_ofz_list()
        
        # Get registered bonds if needed
        registered_secids = get_registered_bonds() if onchain_only else []
        
        # Convert to dictionary format for API
        bonds = []
        for index, row in ofz_list.iterrows():
            secid = row["SECID"]
            
            # Filter by onchain status if requested
            if onchain_only and secid not in registered_secids:
                continue
                
            bonds.append({
                "secid": secid,
                "shortname": row["SHORTNAME"]
            })
        
        return jsonify({
            "timestamp": int(time.time()),
            "count": len(bonds),
            "bonds": bonds,
            "filtered_by_onchain": onchain_only
        })
    except Exception as e:
        logger.error(f"Error fetching bonds list: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/details', methods=['GET'])
def get_all_bond_details():
    """
    Endpoint to get details for all OFZ bonds.
    
    Query Parameters:
        onchain (bool): If 'true', returns only details for bonds that exist on the blockchain
    """
    try:
        # Check if onchain filter is requested
        onchain_only = request.args.get('onchain', '').lower() == 'true'
        
        # Fetch the list of OFZ bonds
        ofz_list = fetch_ofz_list()
        
        # Get registered bonds if needed
        registered_secids = get_registered_bonds() if onchain_only else []
        
        # Get details for each bond
        details_data = {
            "timestamp": int(time.time()), 
            "bonds": {},
            "filtered_by_onchain": onchain_only
        }
        
        for index, row in ofz_list.iterrows():
            secid = row["SECID"]
            
            # Filter by onchain status if requested
            if onchain_only and secid not in registered_secids:
                continue
                
            # Get bond details
            bond_details = get_bond_details(secid)
            
            # Add uint versions for price-related fields
            price_fields = ["initialPrice", "maturityPrice", "couponValue", "accruedInt"]
            for field in price_fields:
                if bond_details[field] is not None:
                    bond_details[f"{field}_uint"] = int(round(float(bond_details[field]) * 1000)) * (Config.PRICE_SCALING_FACTOR // 1000)
            
            # Also add price from the price API if available
            price, is_current = get_price(secid)
            if price is not None:
                bond_details["price"] = float(price)
                bond_details["price_uint"] = int(round(float(price) * 1000)) * (Config.PRICE_SCALING_FACTOR // 1000)
                bond_details["is_current_market_data"] = is_current
                bond_details["data_source"] = "market_price" if is_current else "daily_candle"
            
            details_data["bonds"][secid] = bond_details
        
        return jsonify(details_data)
    except Exception as e:
        logger.error(f"Error fetching bond details: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/details/<secid>', methods=['GET'])
def get_bond_details_for_secid(secid):
    """Endpoint to get details for a specific OFZ bond"""
    try:
        # Check if bond exists by trying to get details
        bond_details = get_bond_details(secid)
        
        if bond_details["maturityAt"] is None:
            return jsonify({"error": f"Bond {secid} not found or details not available"}), 404
        
        # Add uint versions for price-related fields
        price_fields = ["initialPrice", "maturityPrice", "couponValue", "accruedInt"]
        for field in price_fields:
            if bond_details[field] is not None:
                bond_details[f"{field}_uint"] = round(float(bond_details[field]) * Config.PRICE_SCALING_FACTOR)
        
        # Also add price from the price API if available
        price, is_current = get_price(secid)
        if price is not None:
            bond_details["price"] = float(price)
            bond_details["price_uint"] = round(float(price) * Config.PRICE_SCALING_FACTOR)
            bond_details["is_current_market_data"] = is_current
            bond_details["data_source"] = "market_price" if is_current else "daily_candle"
        
        # Return bond details
        return jsonify({
            "timestamp": int(time.time()),
            "details": bond_details
        })
    except Exception as e:
        logger.error(f"Error fetching details for {secid}: {e}")
        return jsonify({"error": str(e)}), 500

# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Not found"}), 404

@app.errorhandler(500)
def server_error(error):
    logger.error(f"Server error: {error}")
    return jsonify({"error": "Internal server error"}), 500

if __name__ == '__main__':
    # Ensure cache directory exists
    Config.ensure_cache_dir()
    
    logger.info(f"Starting OFZ Oracle web server on {Config.HOST}:{Config.PORT}")
    logger.info(f"Signer address: {get_signer_address()}")
    logger.info(f"Cache TTL: {Config.CACHE_TTL} seconds")
    
    app.run(host=Config.HOST, port=Config.PORT, debug=Config.DEBUG)


# Offchain price provider
# Onchain price publisher
