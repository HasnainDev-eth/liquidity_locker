# StampLocker

A comprehensive ERC20 token and liquidity locking solution inspired by UNCX Network.

## Features

### StampTokenLocker
- Lock any ERC20 tokens for a specified duration
- Multiple locks per user and token
- Extend lock duration
- Increase lock amount
- Transfer lock ownership
- Optional lock fees
- Comprehensive event logging

### StampLiquidityLocker
- Lock liquidity pool (LP) tokens from AMMs (Uniswap, PancakeSwap, etc.)
- Support for standard locks and vesting schedules
- Split locks into multiple positions
- Whitelist system for trusted LP tokens
- Vesting claims with linear unlock
- All features from StampTokenLocker

## Use Cases

- **Project Liquidity Locking**: Prevent rug pulls by locking LP tokens
- **Token Vesting**: Implement token vesting schedules for team and investors
- **Trust Building**: Demonstrate commitment to investors through locked liquidity
- **Team Tokens**: Lock team allocations with vesting schedules

## Contracts

- `StampTokenLocker.sol` - Lock regular ERC20 tokens
- `StampLiquidityLocker.sol` - Lock LP tokens with advanced features
- `interfaces/IStampLocker.sol` - Interface definitions

## Key Functions

### Locking Tokens
```solidity
function lockTokens(
    address token,
    uint256 amount,
    uint256 unlockDate,
    string calldata description
) external returns (uint256 lockId);
```

### Locking Liquidity
```solidity
function lockLiquidity(
    address lpToken,
    uint256 amount,
    uint256 unlockDate,
    string calldata description
) external returns (uint256 lockId);
```

### Vesting Lock
```solidity
function lockLiquidityWithVesting(
    address lpToken,
    uint256 amount,
    uint256 vestingStartDate,
    uint256 vestingEndDate,
    string calldata description
) external returns (uint256 lockId);
```

### Withdrawing
```solidity
function withdrawTokens(uint256 lockId) external;
function withdrawLiquidity(uint256 lockId) external;
function claimVesting(uint256 lockId) external;
```

## Security Features

- ReentrancyGuard protection
- SafeERC20 for token transfers
- Owner-only administrative functions
- Optional whitelist for LP tokens
- Support for fee-on-transfer tokens

## Dependencies

- OpenZeppelin Contracts (^5.0.0)
  - IERC20
  - SafeERC20
  - Ownable
  - ReentrancyGuard

## Installation

```bash
npm install @openzeppelin/contracts
```

## Deployment

1. Deploy `StampTokenLocker` for regular token locking
2. Deploy `StampLiquidityLocker` for LP token locking
3. Configure fee settings (optional)
4. Set up LP token whitelist (optional)

## License

MIT
