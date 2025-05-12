import os
import secrets
import re

# Check if .env exists
if os.path.exists('.env'):
    print("Error: .env file already exists")
    exit(1)

# Copy .env.example to .env if it doesn't exist
if not os.path.exists('.env.example'):
    print("Error: .env.example file not found")
    exit(1)

with open('.env.example', 'r') as example_file:
    env_content = example_file.read()

# Generate new private keys
keys = {
    'PROTOCOL_DEPLOYER_PRIVATE_KEY': f"0x{secrets.randbits(256):064x}",
    'IDENTITY_MINTER_PRIVATE_KEY': f"0x{secrets.randbits(256):064x}", 
    'BOND_ISSUER_PRIVATE_KEY': f"0x{secrets.randbits(256):064x}",
    'PRICE_FEED_UPDATER_PRIVATE_KEY': f"0x{secrets.randbits(256):064x}"
}

# Replace each key using regex to match the full line
for key, value in keys.items():
    pattern = f"{key}=0x[0-9a-fA-F]+"
    env_content = re.sub(pattern, f"{key}={value}", env_content)

# Write the updated content to .env
with open('.env', 'w') as env_file:
    env_file.write(env_content)

print(".env file created with new random private keys")

