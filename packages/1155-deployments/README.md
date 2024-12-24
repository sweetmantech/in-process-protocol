# Zora Protocol 1155 Contract Deployments

Contains deployment scripts, deployed addresses and versions for the Zora 1155 Contracts.

## Package contents

- [Deployment scripts](./script/) for deploying Zora Protocol Contracts
- [Deployed addresses](./addresses/) containing deployed addresses and contract versions by chain.

## Deployment Process

### Prerequisites

- Set up environment variables in `.env`:

  ```
  PRIVATE_KEY=your_private_key
  OWNER_ADDRESS=address_that_will_own_the_contracts
  ETHERSCAN_API_KEY=your_etherscan_api_key  # For contract verification
  ```

### Quick Start

Run the entire deployment process with a single command:

```bash
pnpm deploy-all
```

Or follow the step-by-step process below:

### Step 1: Deploy Implementation Contracts

Deploy the implementation contracts:

```bash
pnpm setup:implementations
```

This will:

- Deploy the 1155 implementation contract
- Deploy the factory implementation
- Deploy minter strategies (fixed price, merkle, redeem)
- Save addresses to `./addresses/{chainId}.json`
- Verify all deployed contracts on Basescan

### Step 2: Copy Deployed Addresses

Copy the addresses to the chain config:

```bash
pnpm setup:copy-addresses
```

### Step 3: Deploy Factory Proxy

Deploy the factory proxy that will interact with the implementations:

```bash
pnpm setup:factory-proxy
```

This will:

- Deploy a new factory proxy
- Initialize it with the factory implementation
- Set the owner address
- Verify the proxy contract on Basescan

The factory proxy will be the main entry point for creating new 1155 contracts.

### Verification Notes

- The `--verify` flag will automatically verify all contracts deployed in the script
- Verification might take a few minutes to complete
