import os
from dotenv import load_dotenv

# Load environment variables from .env file if it exists
load_dotenv()

class Config:
    # API and blockchain connection parameters
    OFFCHAIN_PROVIDER_BASE_URL = os.getenv("ONCHAIN_PUBLISHER_OFFCHAIN_PROVIDER_BASE_URL")
    BOND_ORACLE_ADDRESS = os.getenv("ONCHAIN_PUBLISHER_BOND_ORACLE_ADDRESS")
    ETHEREUM_RPC_URL = os.getenv("ONCHAIN_PUBLISHER_ETHEREUM_RPC_URL")
    PUBLISHER_PRIVATE_KEY = os.getenv("ONCHAIN_PUBLISHER_PRIVATE_KEY")
    CHAIN_ID = os.getenv("ONCHAIN_PUBLISHER_CHAIN_ID")
    
    # Application behavior parameters
    POLL_INTERVAL_SECONDS = int(os.getenv("ONCHAIN_PUBLISHER_POLL_INTERVAL_SECONDS"))
    PRICE_CHANGE_THRESHOLD_PERCENT = float(os.getenv("ONCHAIN_PUBLISHER_PRICE_CHANGE_THRESHOLD_PERCENT"))
    BOND_ORACLE_ABI_PATH = os.getenv("ONCHAIN_PUBLISHER_BOND_ORACLE_ABI_PATH")
    LOG_LEVEL = os.getenv("ONCHAIN_PUBLISHER_LOG_LEVEL").upper()

    # Transaction and request parameters
    GAS_LIMIT_UPDATE_PRICE = int(os.getenv("ONCHAIN_PUBLISHER_GAS_LIMIT_UPDATE_PRICE"))
    TX_RECEIPT_TIMEOUT_SECONDS = int(os.getenv("ONCHAIN_PUBLISHER_TX_RECEIPT_TIMEOUT_SECONDS"))
    SCHEDULER_MISFIRE_GRACE_TIME = int(os.getenv("ONCHAIN_PUBLISHER_SCHEDULER_MISFIRE_GRACE_TIME"))
    REQUESTS_TIMEOUT_SECONDS = int(os.getenv("ONCHAIN_PUBLISHER_REQUESTS_TIMEOUT_SECONDS"))

    @staticmethod
    def validate():
        if not Config.BOND_ORACLE_ADDRESS or not Config.BOND_ORACLE_ADDRESS.startswith("0x") or len(Config.BOND_ORACLE_ADDRESS) != 42:
            raise ValueError("Invalid ONCHAIN_PUBLISHER_BOND_ORACLE_ADDRESS format.")
            
        if not Config.PUBLISHER_PRIVATE_KEY:
             raise ValueError("ONCHAIN_PUBLISHER_PRIVATE_KEY is missing.")

        pk_to_check = Config.PUBLISHER_PRIVATE_KEY[2:] if Config.PUBLISHER_PRIVATE_KEY.startswith("0x") else Config.PUBLISHER_PRIVATE_KEY
        if len(pk_to_check) != 64:
            raise ValueError("Invalid ONCHAIN_PUBLISHER_PRIVATE_KEY format. Must be 64 hexadecimal characters.")
        try:
            bytes.fromhex(pk_to_check)
        except ValueError:
            raise ValueError("ONCHAIN_PUBLISHER_PRIVATE_KEY is not a valid hexadecimal string.")

        if Config.CHAIN_ID:
            try:
                Config.CHAIN_ID = int(Config.CHAIN_ID)
            except ValueError:
                raise ValueError("ONCHAIN_PUBLISHER_CHAIN_ID must be an integer if provided.")
