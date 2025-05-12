import os
from dotenv import load_dotenv

# Load environment variables from .env file if it exists
load_dotenv()

class Config:
    # Server settings
    HOST = os.environ.get('OFFCHAIN_PROVIDER_HOST')
    PORT = int(os.environ.get('OFFCHAIN_PROVIDER_PORT'))
    DEBUG = os.environ.get('OFFCHAIN_PROVIDER_DEBUG').lower() == 'true'
    
    # Cache settings
    CACHE_TTL = int(os.environ.get('OFFCHAIN_PROVIDER_CACHE_TTL'))
    CACHE_DIR = os.environ.get('OFFCHAIN_PROVIDER_CACHE_DIR')
    
    # MOEX API settings
    MOEX_API_BASE = "https://iss.moex.com/iss/engines/stock/markets/bonds"
    MOEX_API_HEADERS = {"User-Agent": "ofz-price-bot/1.0"}
    MOEX_API_TIMEOUT = 15
    
    # Blockchain related settings
    PRICE_SCALING_FACTOR = int(os.environ.get('OFFCHAIN_PROVIDER_PRICE_SCALING_FACTOR'))
    BOND_ORACLE_ADDRESS = os.environ.get('OFFCHAIN_PROVIDER_BOND_ORACLE_ADDRESS')
    CHAIN_ID = int(os.environ.get('OFFCHAIN_PROVIDER_CHAIN_ID'))
    SIGNATURE_EXPIRY_SECONDS = int(os.environ.get('OFFCHAIN_PROVIDER_SIGNATURE_EXPIRY_SECONDS'))
    NONCE_FILE = os.environ.get('OFFCHAIN_PROVIDER_NONCE_FILE')
    ETH_RPC_URL = os.environ.get('OFFCHAIN_PROVIDER_ETH_RPC_URL')
    
    # Cache settings for registered bonds list
    REGISTERED_BONDS_CACHE_TTL = 300  # 5 minutes TTL for the registered bonds cache


    @classmethod
    def get_private_key(cls):
        private_key = os.environ.get('OFFCHAIN_PROVIDER_ETH_PRIVATE_KEY')
        
        if private_key.startswith('0x'):
            private_key = private_key[2:]
            
        return private_key
    
    @classmethod
    def ensure_cache_dir(cls):
        os.makedirs(cls.CACHE_DIR, exist_ok=True)
