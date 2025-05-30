# OFZ Oracle Web Server

This web server retrieves OFZ bond prices from the Moscow Exchange (MOEX), signs them with a private key, and serves them through a REST API. The data is cached for 10 seconds to reduce load on the MOEX API.

## Features

- Fetches current OFZ bond prices from MOEX
- Signs price data using Ethereum's signature scheme (compatible with BondOracle.sol)
- Caches responses for 10 seconds (configurable)
- Provides REST API endpoints for accessing the data

## Installation

1. Install dependencies:

```bash
pip install -r requirements.txt
```

2. Set up environment variables (optional):

```bash
# Set private key for signing (if not set, a default test key will be used)
export ETH_PRIVATE_KEY=your_private_key_here

# Configure cache TTL (default is 10 seconds)
export CACHE_TTL=10

# Configure server settings
export HOST=0.0.0.0
export PORT=8080
export DEBUG=true
```

## Usage

Run the server:

```bash
python app.py
```

Or with Gunicorn (production):

```bash
gunicorn -w 4 -b 0.0.0.0:8080 app:app
```

## API Endpoints

### Health Check

```
GET /api/health
```

Returns server status, signer address, and cache settings.

Example response:
```json
{
  "status": "ok",
  "timestamp": 1683456789,
  "signer_address": "0x71C7656EC7ab88b098defB751B7401B5f6d8976F",
  "cache_ttl": 10
}
```

### Get All OFZ Prices

```
GET /api/prices
```

Returns all available OFZ bond prices without signatures.

Example response:
```json
{
  "timestamp": 1683456789,
  "prices": {
    "SU26240RMFS6": {
      "price": 98.75,
      "price_uint": 9875000000,
      "is_current_market_data": true,
      "data_source": "market_price"
    },
    "SU26241RMFS4": {
      "price": 97.22,
      "price_uint": 9722000000,
      "is_current_market_data": false,
      "data_source": "daily_candle"
    }
  }
}
```

To get prices with signatures, add the `sign` query parameter:

```
GET /api/prices?sign
```

Example response with signatures:
```json
{
  "timestamp": 1683456789,
  "prices": {
    "SU26240RMFS6": {
      "price": 98.75,
      "price_uint": 9875000000,
      "is_current_market_data": true,
      "data_source": "market_price",
      "signature": "0x..."
    },
    "SU26241RMFS4": {
      "price": 97.22,
      "price_uint": 9722000000,
      "is_current_market_data": false,
      "data_source": "daily_candle",
      "signature": "0x..."
    }
  }
}
```

### Get Specific OFZ Price

```
GET /api/prices/{secid}
```

Returns price information for a specific OFZ bond without signature.

Example response for `/api/prices/SU26240RMFS6`:
```json
{
  "timestamp": 1683456789,
  "price": {
    "price": 98.75,
    "price_uint": 9875000000,
    "is_current_market_data": true,
    "data_source": "market_price"
  }
}
```

To get price with signature, add the `sign` query parameter:

```
GET /api/prices/{secid}?sign
```

Example response with signature:
```json
{
  "timestamp": 1683456789,
  "price": {
    "price": 98.75,
    "price_uint": 9875000000,
    "is_current_market_data": true,
    "data_source": "market_price",
    "signature": "0x..."
  }
}
```

## Caching

The server caches responses for 10 seconds by default (configurable via `CACHE_TTL` environment variable). This reduces load on the MOEX API and improves response time for frequent requests.

## Signature Generation

Price data is signed using the Ethereum signature scheme, compatible with the `updatePriceFeedWithSignature` function in the BondOracle.sol contract. The signature is generated by:

1. Creating a message hash from the OFZ SECID and price
2. Signing the hash with the private key
3. Formatting the signature as expected by the smart contract

For testing purposes, a default private key is provided. In production, you should set your own private key via the `ETH_PRIVATE_KEY` environment variable.
