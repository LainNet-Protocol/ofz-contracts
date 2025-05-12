"""
Nonce Manager for EIP-712 signatures.

This module handles persistent storage of a single global nonce used in EIP-712 signatures
to prevent replay attacks, even when the service restarts.
"""

import os
import json
import logging
from config import Config

logger = logging.getLogger("nonce_manager")

class NonceManager:
    """Manages a global nonce for EIP-712 signatures with persistence."""
    
    def __init__(self, nonce_file_path: str):
        """
        Initialize the nonce manager.
        
        Args:
            nonce_file_path: Path to the nonce storage file (required).
        """
        if not nonce_file_path:
            raise ValueError("nonce_file_path is required")
            
        self.nonce_file_path = nonce_file_path
        self.current_nonce = 0
        self._ensure_dir_exists()
        self._load_nonce()
        
    def _ensure_dir_exists(self) -> None:
        """Ensure the directory for the nonce file exists."""
        directory = os.path.dirname(self.nonce_file_path)
        os.makedirs(directory, exist_ok=True)
        
    def _load_nonce(self) -> None:
        """Load nonce from file."""
        try:
            if os.path.exists(self.nonce_file_path):
                with open(self.nonce_file_path, 'r') as f:
                    data = json.load(f)
                    self.current_nonce = data.get("nonce", 0)
                logger.info(f"Loaded nonce value {self.current_nonce} from {self.nonce_file_path}")
            else:
                logger.info(f"Nonce file {self.nonce_file_path} does not exist. Starting with nonce 0.")
                self.current_nonce = 0
                self._save_nonce()
        except (json.JSONDecodeError, IOError) as e:
            logger.error(f"Error loading nonce from {self.nonce_file_path}: {e}")
            logger.info("Starting with nonce 0.")
            self.current_nonce = 0
            
    def _save_nonce(self) -> None:
        """Save nonce to file."""
        try:
            with open(self.nonce_file_path, 'w') as f:
                json.dump({"nonce": self.current_nonce}, f, indent=2)
            logger.debug(f"Saved nonce {self.current_nonce} to {self.nonce_file_path}")
        except IOError as e:
            logger.error(f"Error saving nonce to {self.nonce_file_path}: {e}")
            
    def get_next_nonce(self) -> int:
        """
        Get the next nonce and increment.
        
        Returns:
            The next nonce value
        """
        # Increment the nonce
        self.current_nonce += 1
        
        # Save the updated nonce to disk
        self._save_nonce()
        
        # Return the new nonce value
        return self.current_nonce
        
    def get_current_nonce(self) -> int:
        """
        Get the current nonce without incrementing.
        
        Returns:
            The current nonce value
        """
        return self.current_nonce

# Global instance for easy access
_instance = NonceManager(Config.NONCE_FILE)

def get_next_nonce() -> int:
    """
    Get the next nonce value and increment.
    
    Returns:
        The next nonce value
    """
    return _instance.get_next_nonce()

def get_current_nonce() -> int:
    """
    Get the current nonce without incrementing.
    
    Returns:
        The current nonce value
    """
    return _instance.get_current_nonce()
