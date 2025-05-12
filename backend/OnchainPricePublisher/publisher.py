"""
Onchain Price Publisher

This module periodically fetches bond price data from an offchain source
and publishes it to a smart contract when price changes exceed a threshold.
"""

import json
import logging
import sys
import time
from typing import Dict, Optional, Tuple, Any, Union, List

import requests
from apscheduler.schedulers.blocking import BlockingScheduler
from eth_account import Account
from web3 import Web3
from web3.contract import Contract
from web3.middleware import geth_poa_middleware
from web3.types import ChecksumAddress, HexBytes, TxParams, TxReceipt
from eth_abi.abi import encode

from config import Config
from abi_adapter import load_abi_from_file


# Setup module logger
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("OnchainPricePublisher")


class Web3Service:
    """Handles Ethereum blockchain connectivity and interactions."""

    def __init__(self, config: Config, app_logger: logging.Logger):
        """
        Initialize Web3 service.
        
        Args:
            config: Application configuration
            app_logger: Logger instance
        """
        self.config = config
        self.logger = app_logger
        self.w3: Optional[Web3] = None
        self.account: Optional[Account] = None
        
        self._connect_to_ethereum()
        self._setup_account()

    def _connect_to_ethereum(self) -> None:
        """Establish connection to Ethereum node."""
        self.logger.info(f"Connecting to Ethereum RPC at {self.config.ETHEREUM_RPC_URL}...")
        
        try:
            self.w3 = Web3(Web3.HTTPProvider(self.config.ETHEREUM_RPC_URL))
            
            if not self.w3.is_connected():
                raise ConnectionError(f"Failed to connect to Ethereum RPC at {self.config.ETHEREUM_RPC_URL}")
                
            self.logger.info(f"Successfully connected to Ethereum node. Chain ID: {self.w3.eth.chain_id}")
            
            # Apply PoA middleware if needed
            if any(poa_net in self.config.ETHEREUM_RPC_URL for 
                   poa_net in ["rinkeby", "goerli", "polygon", "mumbai"]):
                self.logger.info("Applying PoA middleware for Geth-based PoA chain.")
                self.w3.middleware_onion.inject(geth_poa_middleware, layer=0)
                
        except Exception as e:
            self.logger.error(f"Failed to connect to Ethereum: {str(e)}")
            raise

    def _setup_account(self) -> None:
        """Configure the Ethereum account from private key."""
        try:
            self.account = Account.from_key(self.config.PUBLISHER_PRIVATE_KEY)
            self.w3.eth.default_account = self.account.address
            self.logger.info(f"Publisher account address: {self.account.address}")
        except ValueError as e:
            self.logger.error(f"Failed to setup account: {str(e)}")
            raise
            
    def to_checksum_address(self, address: str) -> ChecksumAddress:
        """Convert string address to checksum address.
        
        Args:
            address: Ethereum address as string
            
        Returns:
            Checksum formatted address
        """
        return Web3.to_checksum_address(address)
        
    def get_transaction_count(self) -> int:
        """Get current transaction count (nonce) for account.
        
        Returns:
            Current nonce
        """
        return self.w3.eth.get_transaction_count(self.account.address)
        
    def get_gas_price(self) -> int:
        """Get current gas price.
        
        Returns:
            Current gas price in Wei
        """
        return self.w3.eth.gas_price
        
    def get_code(self, address: ChecksumAddress) -> bytes:
        """Get contract code at address.
        
        Args:
            address: Contract address
            
        Returns:
            Contract bytecode
        """
        return self.w3.eth.get_code(address)
        
    def sign_transaction(self, transaction: TxParams) -> Any:
        """Sign transaction with account private key.
        
        Args:
            transaction: Transaction parameters
            
        Returns:
            Signed transaction
        """
        return self.w3.eth.account.sign_transaction(
            transaction, 
            private_key=self.config.PUBLISHER_PRIVATE_KEY
        )
        
    def send_raw_transaction(self, raw_tx: bytes) -> HexBytes:
        """Send raw transaction to the network.
        
        Args:
            raw_tx: Raw transaction bytes
            
        Returns:
            Transaction hash
        """
        return self.w3.eth.send_raw_transaction(raw_tx)
        
    def wait_for_transaction_receipt(self, tx_hash: HexBytes, timeout: int) -> TxReceipt:
        """Wait for transaction receipt.
        
        Args:
            tx_hash: Transaction hash
            timeout: Timeout in seconds
            
        Returns:
            Transaction receipt
        """
        return self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=timeout)


class ContractService:
    """Manages smart contract interactions."""
    
    def __init__(
        self, 
        web3_service: Web3Service, 
        config: Config, 
        app_logger: logging.Logger
    ):
        """
        Initialize contract service.
        
        Args:
            web3_service: Initialized Web3Service instance
            config: Application configuration
            app_logger: Logger instance
        """
        self.web3 = web3_service
        self.config = config
        self.logger = app_logger
        self.contract: Optional[Contract] = None
        
        self._load_contract()
        
    def _load_contract(self) -> None:
        """Load and validate contract instance."""
        try:
            # Load contract ABI
            self.logger.debug(f"Loading ABI from: {self.config.BOND_ORACLE_ABI_PATH}")
            abi_data = self._load_abi()
            
            # Validate contract address
            contract_address = self.web3.to_checksum_address(self.config.BOND_ORACLE_ADDRESS)
            self._validate_contract_code(contract_address)
            
            # Create contract instance
            self.contract = self.web3.w3.eth.contract(
                address=contract_address, 
                abi=abi_data
            )
            self.logger.info(f"BondOracle contract loaded at address: {self.config.BOND_ORACLE_ADDRESS}")
            
        except (FileNotFoundError, json.JSONDecodeError) as e:
            self.logger.error(f"Failed to load contract ABI: {str(e)}")
            raise
        except ValueError as e:
            self.logger.error(f"Contract validation error: {str(e)}")
            raise
    
    def _load_abi(self) -> List[Dict[str, Any]]:
        """Load contract ABI from file using the ABI adapter.
        
        The adapter handles different ABI formats including:
        - Simple ABI arrays
        - Foundry contract output (with 'abi' field)
        - Hardhat/Truffle artifacts
        
        Returns:
            Contract ABI
            
        Raises:
            FileNotFoundError: If ABI file doesn't exist
            json.JSONDecodeError: If ABI file has invalid JSON
            ValueError: If ABI can't be extracted
        """
        try:
            self.logger.info(f"Loading ABI from file: {self.config.BOND_ORACLE_ABI_PATH}")
            return load_abi_from_file(self.config.BOND_ORACLE_ABI_PATH)
        except FileNotFoundError:
            self.logger.error(f"ABI file not found: {self.config.BOND_ORACLE_ABI_PATH}")
            raise
        except json.JSONDecodeError:
            self.logger.error(f"Invalid JSON in ABI file: {self.config.BOND_ORACLE_ABI_PATH}")
            raise
        except ValueError as e:
            self.logger.error(f"Failed to extract ABI: {str(e)}")
            raise
    
    def _validate_contract_code(self, address: ChecksumAddress) -> None:
        """
        Validate that contract code exists at address.
        
        Args:
            address: Contract address to validate
            
        Raises:
            ValueError: If no contract code exists at address
        """
        self.logger.info(f"Checking for contract code at address: {address} on chain ID {self.web3.w3.eth.chain_id}...")
        contract_code = self.web3.get_code(address)
        
        if not contract_code or len(contract_code) == 0:
            msg = (f"No contract code found at address {address}. "
                   "Ensure ONCHAIN_PUBLISHER_BOND_ORACLE_ADDRESS is correct and contract is deployed.")
            self.logger.error(msg)
            raise ValueError(msg)
            
        self.logger.info(f"Contract code found at {address} (length: {len(contract_code)} bytes).")
    
    def get_bond_for_secid(self, secid: str) -> str:
        """
        Get bond address for security ID.
        
        Args:
            secid: Security ID
            
        Returns:
            Bond address
        """
        return self.contract.functions.secidToBond(secid).call()
        
    def get_all_registered_secids(self) -> list:
        """
        Get all SECIDs registered in the BondOracle contract.
        
        This retrieves all bond tokens registered in the oracle and their 
        corresponding SECIDs for which we need to fetch prices.
        
        Returns:
            List of registered SECIDs
        """
        # This would ideally use a contract event or view function that
        # returns all registered SECIDs, but since we don't have that,
        # we'll use a workaround to check known SECIDs
        
        # First, fetch the list of available bonds from the OffchainPriceProvider API
        # to get a candidate list of SECIDs to check
        self.logger.info(f"Fetching candidate bond list from offchain provider API")
        try:
            response = requests.get(
                f"{self.config.OFFCHAIN_PROVIDER_BASE_URL}/api/bonds",
                timeout=self.config.REQUESTS_TIMEOUT_SECONDS
            )
            response.raise_for_status()
            
            bonds_data = response.json()
            candidate_secids = [bond["secid"] for bond in bonds_data.get("bonds", [])]
            self.logger.info(f"Found {len(candidate_secids)} candidate SECIDs to check in the oracle")
            
            # Check each candidate SECID to see if it's registered in the oracle
            registered_secids = []
            for secid in candidate_secids:
                bond_address = self.get_bond_for_secid(secid)
                if bond_address != "0x0000000000000000000000000000000000000000":
                    self.logger.debug(f"SECID {secid} is registered in the oracle with bond address {bond_address}")
                    registered_secids.append(secid)
            
            self.logger.info(f"Found {len(registered_secids)} registered SECIDs in the oracle")
            return registered_secids
            
        except requests.exceptions.RequestException as e:
            self.logger.error(f"Failed to fetch candidate bond list: {str(e)}")
            # If we can't get the candidate list, return an empty list
            # This is safer than trying to make up SECIDs to check
            return []
        except Exception as e:
            self.logger.error(f"Error while getting registered SECIDs: {str(e)}")
            return []
    
    def get_price_feed(self, bond_address: ChecksumAddress) -> Tuple[int, int, int]:
        """
        Get price feed information for bond.
        
        Args:
            bond_address: Bond contract address
            
        Returns:
            Tuple of (price, lastUpdated, maturityAt)
        """
        return self.contract.functions.getPriceFeed(bond_address).call()
    
    def build_update_price_transaction(
        self, 
        secid: str, 
        price_uint: int,
        deadline: int,
        nonce: int,
        signature_bytes: bytes
    ) -> Any:
        """
        Build transaction for updating price with signature.
        
        Args:
            secid: Security ID
            price_uint: Price as unsigned integer
            deadline: Timestamp after which the signature is no longer valid
            nonce: Nonce to prevent replay attacks
            signature_bytes: Signature bytes
            
        Returns:
            Transaction function call
        """
        self.logger.info(f"Building transaction with parameters: secid={secid}, price={price_uint}, deadline={deadline}, nonce={nonce}, signature_len={len(signature_bytes)}")
        
        return self.contract.functions.updatePriceFeedWithSignature( 
            secid, price_uint, deadline, nonce, signature_bytes 
        )
        

class PriceService:
    """Handles price data fetching and processing."""
    
    def __init__(
        self, 
        web3_service: Web3Service,
        contract_service: ContractService,
        config: Config, 
        app_logger: logging.Logger
    ):
        """
        Initialize price service.
        
        Args:
            web3_service: Initialized Web3Service instance
            contract_service: Initialized ContractService instance
            config: Application configuration
            app_logger: Logger instance
        """
        self.web3 = web3_service
        self.contract = contract_service
        self.config = config
        self.logger = app_logger
        
    def fetch_offchain_prices(self) -> Dict[str, Dict[str, Any]]:
        """
        Fetch prices from offchain provider only for registered bonds.
        
        Returns:
            Dictionary of price data by security ID
            
        Raises:
            requests.exceptions.RequestException: For request errors
            ValueError: For response parsing errors
        """
        # First, get the list of all registered SECIDs
        registered_secids = self.contract.get_all_registered_secids()
        
        self.logger.info(f"Fetching prices for {len(registered_secids)} registered bonds")
        
        if not registered_secids:
            self.logger.warning("No registered bonds found. Nothing to fetch.")
            return {}
        
        prices = {}
        
        for secid in registered_secids:
            try:
                # Construct the URL for the specific SECID with signature
                url = f"{self.config.OFFCHAIN_PROVIDER_BASE_URL}/api/prices/{secid}?sign=true"
                self.logger.debug(f"Fetching price for SECID {secid} from: {url}")
                
                response = requests.get(
                    url,
                    timeout=self.config.REQUESTS_TIMEOUT_SECONDS
                )
                response.raise_for_status()
                
                data = response.json()
                price_info = data.get("price", {})
                
                if price_info:
                    prices[secid] = price_info
                    self.logger.debug(f"Successfully fetched price for {secid}: {price_info.get('price')}")
                
            except requests.exceptions.RequestException as e:
                self.logger.error(f"Failed to fetch price for {secid}: {str(e)}")
                # Continue with other SECIDs even if one fails
                continue
            except (json.JSONDecodeError, KeyError) as e:
                self.logger.error(f"Failed to parse response for {secid}: {str(e)}")
                continue
                
        self.logger.info(f"Successfully fetched {len(prices)} price entries from offchain provider.")
        return prices
            
    def get_onchain_price(self, secid: str) -> Optional[int]:
        """
        Get current onchain price for security ID.
        
        Args:
            secid: Security ID
            
        Returns:
            Current price or None if SECID is not registered
        """
        self.logger.debug(f"Getting onchain price for SECID: {secid}")
        
        bond_address_str = self.contract.get_bond_for_secid(secid)
        if bond_address_str == "0x0000000000000000000000000000000000000000":
            self.logger.warning(f"SECID {secid} not registered in BondOracle contract (bond address is zero).")
            return None
            
        bond_address = self.web3.to_checksum_address(bond_address_str)
        bond_info = self.contract.get_price_feed(bond_address)
        
        self.logger.debug(f"Onchain price for {secid} (bond: {bond_address}): {bond_info[0]}")
        return bond_info[0]
        
    def prepare_signature(self, signature_hex: str, secid: str) -> bytes:
        """
        Process signature from OffchainPriceProvider for BondOracle contract.
        
        The signature from OffchainPriceProvider is now in ABI-encoded format
        expected by the contract's abi.decode(_signature, (bytes32, bytes32, uint8))
        function.
        
        Args:
            signature_hex: Signature as hex string from OffchainPriceProvider (ABI-encoded)
            secid: Security ID for logging
            
        Returns:
            Signature as bytes
            
        Raises:
            TypeError: If signature is not a string
            ValueError: If signature is not valid hex
        """
        self.logger.debug(f"Processing signature for {secid}: '{signature_hex}'")
        
        if not isinstance(signature_hex, str):
            msg = f"Signature for {secid} must be a string, got: {type(signature_hex)}"
            self.logger.error(msg)
            raise TypeError(msg)
            
        try:
            # Remove '0x' prefix if present
            hex_to_convert = signature_hex[2:] if signature_hex.startswith("0x") else signature_hex
            
            # ABI-encoded signature will be longer than the previous concatenated format
            # Expected: 32 bytes for r + 32 bytes for s + 32 bytes for v (padded) = 96 bytes
            # The typical length is 96 bytes (192 hex chars), but we'll be more flexible here
            
            # Convert directly to bytes
            signature_bytes = bytes.fromhex(hex_to_convert)
            
            # Log the signature info for debugging
            self.logger.debug(f"Signature length: {len(signature_bytes)} bytes")
            self.logger.debug(f"Using ABI-encoded signature format which is properly decoded by the contract")
            
            return signature_bytes
            
        except ValueError as e:
            self.logger.error(f"Invalid signature format for {secid}: {str(e)}")
            raise
            
    def should_update_price(self, secid: str, new_price: int, current_price: Optional[int]) -> bool:
        """
        Determine if price should be updated based on change threshold.
        
        Args:
            secid: Security ID
            new_price: New price value
            current_price: Current onchain price or None
            
        Returns:
            True if price should be updated, False otherwise
        """
        # SECID not registered
        if current_price is None:
            self.logger.info(f"SECID {secid} not registered onchain. Skipping update.")
            return False
            
        # Initial price (zero)
        if current_price == 0:
            self.logger.info(f"Current onchain price for {secid} is 0. Update needed.")
            return True
            
        # The current_price and new_price might be at different scales
        # From logs we see the onchain price is already in the same format as the offchain price
        # So we don't need to adjust the price for comparison
        
        # Calculate price change percentage directly
        price_change_percent = (abs(new_price - current_price) / current_price) * 100
            
        self.logger.info(
            f"SECID: {secid}, Current Onchain: {current_price}, New Offchain: {new_price}, "
            f"Change: {price_change_percent:.2f}%"
        )
        
        # Check if change exceeds threshold
        if price_change_percent >= self.config.PRICE_CHANGE_THRESHOLD_PERCENT:
            self.logger.info(f"Price change for {secid} ({price_change_percent:.2f}%) meets/exceeds threshold. Update needed.")
            return True
        else:
            self.logger.info(f"Price change for {secid} ({price_change_percent:.2f}%) below threshold. No update needed.")
            return False


class TransactionService:
    """Handles blockchain transaction creation and submission."""
    
    def __init__(
        self, 
        web3_service: Web3Service,
        contract_service: ContractService,
        config: Config, 
        app_logger: logging.Logger
    ):
        """
        Initialize transaction service.
        
        Args:
            web3_service: Initialized Web3Service instance
            contract_service: Initialized ContractService instance
            config: Application configuration
            app_logger: Logger instance
        """
        self.web3 = web3_service
        self.contract = contract_service
        self.config = config
        self.logger = app_logger
        
    def send_update_price_transaction(
        self, 
        secid: str, 
        price_uint: int,
        deadline: int,
        nonce: int,
        signature_bytes: bytes
    ) -> bool:
        """
        Send transaction to update price onchain.
        
        Args:
            secid: Security ID
            price_uint: Price as unsigned integer
            deadline: Timestamp after which the signature is no longer valid
            nonce: Nonce to prevent replay attacks
            signature_bytes: Signature as bytes
            
        Returns:
            True if transaction was successful
            
        Raises:
            RuntimeError: If transaction fails
        """
        self.logger.info(f"Attempting to update price for {secid} to {price_uint} onchain. Deadline: {deadline}, Nonce: {nonce}")
        
        contract_fn_call = self.contract.build_update_price_transaction(
            secid, price_uint, deadline, nonce, signature_bytes
        )
        
        return self._send_transaction(contract_fn_call, secid)
        
    def _send_transaction(self, contract_function_call: Any, secid: str) -> bool:
        """
        Build, sign and send transaction.
        
        Args:
            contract_function_call: Contract function to call
            secid: Security ID for logging
            
        Returns:
            True if transaction succeeded
            
        Raises:
            RuntimeError: If transaction fails or is reverted
        """
        self.logger.debug(f"Preparing transaction for {secid}...")
        
        try:
            # Get nonce for transaction
            nonce = self.web3.get_transaction_count()
            
            # Build transaction parameters
            txn_params = {
                'from': self.web3.account.address,
                'nonce': nonce,
                'gas': self.config.GAS_LIMIT_UPDATE_PRICE,
                'gasPrice': self.web3.get_gas_price()
            }
            
            # Add chainId if configured
            if self.config.CHAIN_ID:
                txn_params['chainId'] = int(self.config.CHAIN_ID)
            
            # Build the transaction
            tx = contract_function_call.build_transaction(txn_params)
            
            # Sign the transaction
            signed_tx = self.web3.sign_transaction(tx)
            
            # Send the transaction
            tx_hash = self.web3.send_raw_transaction(signed_tx.rawTransaction)
            tx_hash_hex = tx_hash.hex()
            
            self.logger.info(f"Transaction sent for {secid}. Tx Hash: {tx_hash_hex}. Waiting for receipt...")
            
            # Wait for transaction receipt
            tx_receipt = self.web3.wait_for_transaction_receipt(
                tx_hash, 
                self.config.TX_RECEIPT_TIMEOUT_SECONDS
            )
            
            # Check transaction status
            if tx_receipt.status == 1:
                self.logger.info(f"Tx for {secid} successful. Block: {tx_receipt.blockNumber}")
                return True
            else:
                msg = f"Tx for {secid} reverted by EVM. Hash: {tx_hash_hex}. Receipt: {tx_receipt}"
                self.logger.error(msg)
                raise RuntimeError(msg)
                
        except Exception as e:
            self.logger.error(f"Transaction error for {secid}: {str(e)}")
            raise


class PricePublisher:
    """Main service that coordinates price updates."""
    
    def __init__(self, config: Config, app_logger: logging.Logger):
        """
        Initialize price publisher service.
        
        Args:
            config: Application configuration
            app_logger: Logger instance
        """
        self.config = config
        self.logger = app_logger
        
        # Log configuration parameters
        self._log_config_parameters()
        
        # Initialize services
        self.web3_service = Web3Service(config, app_logger)
        self.contract_service = ContractService(self.web3_service, config, app_logger)
        self.price_service = PriceService(
            self.web3_service, 
            self.contract_service, 
            config, 
            app_logger
        )
        self.tx_service = TransactionService(
            self.web3_service, 
            self.contract_service, 
            config, 
            app_logger
        )
        
    def _log_config_parameters(self) -> None:
        """Log important configuration parameters."""
        self.logger.info(f"Using OFFCHAIN_PROVIDER_BASE_URL: {self.config.OFFCHAIN_PROVIDER_BASE_URL}")
        self.logger.info(f"Using GAS_LIMIT_UPDATE_PRICE: {self.config.GAS_LIMIT_UPDATE_PRICE}")
        self.logger.info(f"Using TX_RECEIPT_TIMEOUT_SECONDS: {self.config.TX_RECEIPT_TIMEOUT_SECONDS}")
        self.logger.info(f"Using SCHEDULER_MISFIRE_GRACE_TIME: {self.config.SCHEDULER_MISFIRE_GRACE_TIME}")
        self.logger.info(f"Using REQUESTS_TIMEOUT_SECONDS: {self.config.REQUESTS_TIMEOUT_SECONDS}")
        
    def process_single_price_update(self, secid: str, offchain_data: Dict[str, Any]) -> None:
        """
        Process a single security ID for potential price update.
        
        Args:
            secid: Security ID to process
            offchain_data: Price data from offchain provider
        """
        # Extract price, signature, deadline, and nonce from offchain data
        new_price_uint = offchain_data.get("price_uint")
        signature = offchain_data.get("signature")
        deadline = offchain_data.get("deadline")
        nonce = offchain_data.get("nonce")
        
        # Skip if any required data is missing
        if new_price_uint is None or signature is None or deadline is None or nonce is None:
            self.logger.warning(f"Missing required data for {secid} in offchain data. Skipping.")
            self.logger.debug(f"Data received: price_uint={new_price_uint}, signature={'present' if signature else 'missing'}, deadline={deadline}, nonce={nonce}")
            return
            
        self.logger.info(f"Processing {secid}: New offchain price_uint = {new_price_uint}, deadline = {deadline}, nonce = {nonce}")
        
        try:
            # Get current onchain price
            current_onchain_price = self.price_service.get_onchain_price(secid)
            
            # Determine if update is needed
            if self.price_service.should_update_price(secid, new_price_uint, current_onchain_price):
                # Prepare signature
                signature_bytes = self.price_service.prepare_signature(signature, secid)
                
                # Check if deadline is in the future
                current_time = int(time.time())
                if deadline <= current_time:
                    self.logger.warning(f"Signature for {secid} has expired (deadline: {deadline}, current time: {current_time}). Skipping.")
                    return
                
                # CRITICAL: When using the signature, we must use the EXACT price, deadline, and nonce that were signed
                # The signature verification in the contract will fail if we modify any of these values
                self.logger.info(
                    f"Sending price update for {secid} with original price: {new_price_uint}, deadline: {deadline}, nonce: {nonce}"
                )
                
                # Send transaction with all the required parameters
                self.tx_service.send_update_price_transaction(
                    secid, 
                    new_price_uint,  # Use the original price from the signature
                    deadline,
                    nonce,
                    signature_bytes
                )
                
        except Exception as e:
            self.logger.error(f"Failed to process price update for {secid}: {str(e)}")
            # Don't re-raise to allow processing of other securities
        
    def run_update_cycle(self) -> None:
        """Run a complete price update cycle."""
        self.logger.info("--- Starting new price update cycle ---")
        
        try:
            # Fetch prices from offchain provider only for registered bonds
            # This new approach:
            # 1. First gets the list of all registered bonds from the oracle
            # 2. Then fetches prices only for those registered bonds
            # 3. Processes each price update individually
            offchain_prices_data = self.price_service.fetch_offchain_prices()
            
            if not offchain_prices_data:
                self.logger.warning("No registered bonds found or no price data returned. Skipping current update cycle.")
                return
                
            # Process each security ID
            self.logger.info(f"Processing {len(offchain_prices_data)} bond price updates")
            for secid, data in offchain_prices_data.items():
                self.process_single_price_update(secid, data)
                
            self.logger.info("--- Price update cycle finished ---")
            
        except Exception as e:
            self.logger.error(f"Error in update cycle: {str(e)}")
            self.logger.info("--- Price update cycle aborted ---")


def setup_logging(config_obj: Config) -> logging.Logger:
    """
    Set up application logging.
    
    Args:
        config_obj: Application configuration
        
    Returns:
        Configured logger instance
    """
    # Get log level from config
    log_level_name = getattr(config_obj, 'LOG_LEVEL', 'INFO').upper()
    log_level = getattr(logging, log_level_name, logging.INFO)
    
    # Configure logging
    logging.basicConfig(
        level=log_level, 
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        force=True
    ) 
    
    # Ensure all handlers use correct level
    for handler in logging.root.handlers:
        handler.setLevel(log_level)
        
    # Create and return main logger
    return logging.getLogger("OnchainPricePublisher.Main")


def main() -> None:
    """
    Main application entry point.
    
    Initializes services, performs initial price update cycle,
    and starts the scheduler for recurring updates.
    """
    main_logger = setup_logging(Config)
    scheduler_instance = None
    
    try:
        # Validate configuration
        main_logger.info("Validating configuration...")
        Config.validate()
        main_logger.info("Configuration validated successfully.")
        
        # Initialize price publisher
        main_logger.info("Initializing PricePublisher...")
        publisher_instance = PricePublisher(Config, main_logger)
        main_logger.info("PricePublisher initialized successfully.")
        
        # Perform initial update cycle
        main_logger.info("Performing initial price update cycle...")
        publisher_instance.run_update_cycle()
        main_logger.info("Initial price update cycle finished.")
        
        # Start scheduler for recurring updates
        scheduler_instance = BlockingScheduler(timezone="UTC", logger=main_logger)
        scheduler_instance.add_job(
            publisher_instance.run_update_cycle,
            'interval',
            seconds=Config.POLL_INTERVAL_SECONDS,
            misfire_grace_time=Config.SCHEDULER_MISFIRE_GRACE_TIME
        )
        
        main_logger.info(
            f"Scheduler started. Job interval: {Config.POLL_INTERVAL_SECONDS}s, "
            f"Misfire grace: {Config.SCHEDULER_MISFIRE_GRACE_TIME}s."
        )
        main_logger.info("Press Ctrl+C to exit.")
        
        # Start the scheduler
        scheduler_instance.start()
        
    except KeyboardInterrupt:
        main_logger.info("Scheduler stopped by user.")
    except Exception as e:
        main_logger.critical(f"A critical error occurred: {e}", exc_info=True)
        sys.exit(1)
    finally:
        # Ensure scheduler is properly shut down
        if scheduler_instance and scheduler_instance.running:
            main_logger.info("Shutting down scheduler...")
            scheduler_instance.shutdown()
        main_logger.info("OnchainPricePublisher service shut down.")


if __name__ == "__main__":
    main()
