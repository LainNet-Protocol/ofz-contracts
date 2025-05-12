import os
import json
import time

class CacheManager:
    """
    Handles caching of price data with a specified TTL (time-to-live)
    """
    
    def __init__(self, ttl_seconds=10):
        """
        Initialize the cache manager
        
        Args:
            ttl_seconds (int): Cache time-to-live in seconds
        """
        self.ttl_seconds = ttl_seconds
        self.cache_file = os.path.join('backend', 'OffchainPriceProvider', 'cache', 'price_cache.json')
        
        # Create cache directory if it doesn't exist
        os.makedirs(os.path.dirname(self.cache_file), exist_ok=True)
    
    def get_cached_data(self):
        """
        Get cached data if it exists and is still valid (not expired)
        
        Returns:
            dict: Cached data or None if cache doesn't exist or is expired
        """
        if not os.path.exists(self.cache_file):
            return None
        
        # Check if file is older than TTL
        file_mod_time = os.path.getmtime(self.cache_file)
        if time.time() - file_mod_time > self.ttl_seconds:
            return None  # Cache expired
        
        try:
            with open(self.cache_file, 'r') as f:
                data = json.load(f)
                return data
        except (json.JSONDecodeError, IOError):
            # If file is corrupted or can't be read, return None
            return None
    
    def cache_data(self, data):
        """
        Cache the provided data to file
        
        Args:
            data (dict): Data to cache
        
        Returns:
            bool: True if caching was successful, False otherwise
        """
        try:
            with open(self.cache_file, 'w') as f:
                json.dump(data, f, indent=2)
            return True
        except IOError:
            # If file can't be written, fail silently
            return False
    
    def clear_cache(self):
        """
        Clear the cache file (if it exists)
        
        Returns:
            bool: True if cache was cleared successfully, False otherwise
        """
        if os.path.exists(self.cache_file):
            try:
                os.remove(self.cache_file)
                return True
            except IOError:
                return False
        return True  # Cache doesn't exist, so it's already "cleared"
