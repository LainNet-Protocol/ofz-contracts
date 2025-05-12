#!/usr/bin/env python3
"""
Entry point script for the OFZ Oracle Web Server
This script verifies the environment and launches the web server
"""

import os
import sys
import logging
from importlib import import_module

# Configure logging
logging.basicConfig(level=logging.INFO, 
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('ofz_oracle_runner')

def check_dependencies():
    """Check if all required dependencies are installed"""
    required_modules = [
        'flask', 'pandas', 'requests', 'web3'
    ]
    
    missing = []
    for module in required_modules:
        try:
            import_module(module)
        except ImportError:
            missing.append(module)
    
    if missing:
        logger.error(f"Missing dependencies: {', '.join(missing)}")
        logger.error("Please install required dependencies: pip install -r requirements.txt")
        return False
    
    return True

def prepare_environment():
    """Prepare the environment for running the server"""
    # Ensure cache directory exists
    cache_dir = os.path.join('backend', 'OffchainPriceProvider', 'cache')
    os.makedirs(cache_dir, exist_ok=True)
    logger.info(f"Cache directory created: {cache_dir}")
    
    # Check for private key in environment
    if not os.environ.get('ETH_PRIVATE_KEY'):
        logger.warning("ETH_PRIVATE_KEY not set in environment. Using default test key.")
        logger.warning("For production use, set a secure private key.")
    
    return True

def main():
    """Main entry point"""
    logger.info("Starting OFZ Oracle Web Server setup...")
    
    # Check dependencies
    if not check_dependencies():
        return 1
    
    # Prepare environment
    if not prepare_environment():
        return 1
    
    # Import app only after dependencies check passes
    from app import app
    from signature_utils import get_signer_address
    from config import Config
    
    logger.info("Environment ready")
    logger.info(f"Signer address: {get_signer_address()}")
    logger.info(f"Server will run on {Config.HOST}:{Config.PORT}")
    logger.info(f"Cache TTL: {Config.CACHE_TTL} seconds")
    logger.info("Starting server...")
    
    # Start the Flask app
    app.run(host=Config.HOST, port=Config.PORT, debug=Config.DEBUG)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
