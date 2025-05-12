"""
ABI adapter to extract ABI from different file formats
"""
import json
import logging

logger = logging.getLogger("OnchainPricePublisher.ABIAdapter")

def load_abi_from_file(filepath: str) -> list:
    """
    Load ABI from a file, handling different file formats.
    
    Args:
        filepath: Path to the ABI file
        
    Returns:
        ABI as a list
        
    Raises:
        FileNotFoundError: If file doesn't exist
        json.JSONDecodeError: If file has invalid JSON
        ValueError: If ABI can't be extracted
    """
    try:
        with open(filepath, 'r') as f:
            file_content = json.load(f)
            
        logger.info(f"Loaded JSON from {filepath}")
        
        # Check file structure and extract ABI
        if isinstance(file_content, list):
            # Simple ABI array format
            logger.info("Detected simple ABI array format")
            return file_content
            
        elif isinstance(file_content, dict):
            # Check for Foundry format (has 'abi' field)
            if 'abi' in file_content:
                logger.info("Detected Foundry contract JSON format")
                return file_content['abi']
                
            # Check for Hardhat/Truffle artifacts format
            elif all(key in file_content for key in ['contractName', 'abi']):
                logger.info("Detected Hardhat/Truffle artifacts format")
                return file_content['abi']
                
        # If we get here, we couldn't identify the format
        raise ValueError(f"Unrecognized ABI format in {filepath}")
        
    except FileNotFoundError:
        logger.error(f"ABI file not found: {filepath}")
        raise
    except json.JSONDecodeError:
        logger.error(f"Invalid JSON in ABI file: {filepath}")
        raise
    except Exception as e:
        logger.error(f"Error loading ABI from {filepath}: {str(e)}")
        raise ValueError(f"Failed to load ABI: {str(e)}")
