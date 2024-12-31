# Multi-Token Index Fund Smart Contract

## About

This smart contract implements a decentralized index fund that can hold and manage multiple SIP-010 compliant tokens on the Stacks blockchain. The contract allows investors to deposit and withdraw tokens while maintaining predefined allocation weights for each token in the index. It includes features such as automated portfolio rebalancing, management fees, and administrative controls.

## Features

- Support for multiple SIP-010 compliant tokens
- Automated portfolio rebalancing based on target weights
- Management fee calculation and collection
- Deposit and withdrawal functionality
- Emergency pause mechanism
- Administrative controls for token management
- Real-time price updates
- Comprehensive balance tracking

## Technical Specifications

- Maximum number of supported tokens: 10
- Annual management fee: 0.3% (30 basis points)
- Portfolio rebalance threshold: 5% (500 basis points)
- Token standard: SIP-010 compliant

## Core Functions

### For Investors

1. `deposit-tokens`
   - Parameters: token-identifier, token-contract-instance, deposit-amount
   - Allows investors to deposit tokens into the index fund
   - Requires contract to not be paused
   - Updates investor balances and total supply

2. `withdraw-tokens`
   - Parameters: token-identifier, token-contract-instance, withdrawal-amount
   - Enables investors to withdraw their tokens
   - Automatically calculates and deducts management fees
   - Updates balances accordingly

### For Administrators

1. `add-token-to-index`
   - Parameters: token-identifier, weight-percentage, token-contract-id
   - Adds new tokens to the index
   - Sets initial allocation weights
   - Restricted to administrator only

2. `update-token-price`
   - Parameters: token-identifier, current-price
   - Updates market prices for tokens
   - Used for portfolio rebalancing calculations

3. `rebalance-portfolio`
   - Triggers portfolio rebalancing when deviation exceeds threshold
   - Only executable by administrator
   - Updates last rebalance block height

4. `pause-contract` / `resume-contract`
   - Emergency functions to pause/resume contract operations
   - Restricted to administrator only

### Read-Only Functions

1. `get-investor-balance`
   - Parameters: investor-address
   - Returns the token balance for a specific investor

2. `get-token-weight`
   - Parameters: token-identifier
   - Returns the target allocation weight for a specific token

3. `get-index-tokens`
   - Returns the list of all supported tokens in the index

4. `get-total-fund-supply`
   - Returns the total supply of the index fund

## Error Codes

- u100: Unauthorized access
- u101: Invalid deposit amount
- u102: Insufficient user balance
- u103: Unsupported token type
- u104: Rebalance threshold not met
- u105: Rebalance operation failed
- u106: Invalid token identifier
- u107: Invalid allocation percentage
- u108: Invalid token price
- u109: Invalid token contract address

## Security Features

1. Access Control
   - Administrator-only functions
   - Contract pause mechanism
   - Balance validation checks

2. Safety Checks
   - Token support verification
   - Balance sufficiency verification
   - Valid amount verification
   - Contract state verification

## Management Fee Calculation

The management fee is calculated based on:
- Annual rate of 0.3%
- Pro-rata calculation based on blocks elapsed since last rebalance
- Deducted automatically during withdrawals

## Portfolio Rebalancing

The rebalancing process:
1. Calculates total portfolio deviation
2. Compares against 5% threshold
3. Executes rebalancing if threshold is exceeded
4. Updates last rebalance block height

## Usage Example

```clarity
;; Deposit tokens
(contract-call? .index-fund deposit-tokens 
    "TOKEN-A" 
    'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.token-a 
    u1000)

;; Withdraw tokens
(contract-call? .index-fund withdraw-tokens
    "TOKEN-A"
    'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.token-a
    u500)