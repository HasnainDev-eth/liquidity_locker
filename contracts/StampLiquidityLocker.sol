// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title StampLiquidityLocker
 * @notice Locks liquidity pool (LP) tokens for a specified duration
 * @dev Designed for AMM LP tokens (Uniswap V2/V3, PancakeSwap, etc.)
 * Provides security and trust for DeFi projects by preventing rug pulls
 */
contract StampLiquidityLocker is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct LiquidityLock {
        uint256 lockId;
        address lpToken;
        address owner;
        uint256 amount;
        uint256 lockDate;
        uint256 unlockDate;
        string description;
        bool withdrawn;
        bool isVesting;
        uint256 vestingStartDate;
        uint256 vestingEndDate;
        uint256 totalVestingAmount;
        uint256 withdrawnAmount;
    }

    // Lock ID counter
    uint256 public lockIdCounter;

    // Lock ID => Lock details
    mapping(uint256 => LiquidityLock) public locks;

    // User address => Lock IDs
    mapping(address => uint256[]) public userLockIds;

    // LP Token address => Lock IDs
    mapping(address => uint256[]) public lpTokenLockIds;

    // Fee settings (in basis points, 100 = 1%)
    uint256 public lockFee = 0; // Default 0%
    address public feeReceiver;

    // Whitelist for trusted LP tokens (optional security feature)
    mapping(address => bool) public whitelistedLpTokens;
    bool public whitelistEnabled = false;

    // Events
    event LiquidityLocked(
        uint256 indexed lockId,
        address indexed lpToken,
        address indexed owner,
        uint256 amount,
        uint256 unlockDate,
        string description,
        bool isVesting
    );

    event LiquidityWithdrawn(
        uint256 indexed lockId,
        address indexed lpToken,
        address indexed owner,
        uint256 amount
    );

    event VestingClaimed(
        uint256 indexed lockId,
        address indexed owner,
        uint256 amount,
        uint256 totalClaimed
    );

    event LockExtended(
        uint256 indexed lockId,
        uint256 oldUnlockDate,
        uint256 newUnlockDate
    );

    event LockOwnershipTransferred(
        uint256 indexed lockId,
        address indexed oldOwner,
        address indexed newOwner
    );

    event LockAmountIncreased(
        uint256 indexed lockId,
        uint256 oldAmount,
        uint256 newAmount
    );

    event LockSplit(
        uint256 indexed originalLockId,
        uint256 indexed newLockId,
        uint256 originalAmount,
        uint256 newAmount
    );

    event FeeUpdated(uint256 newFee);
    event FeeReceiverUpdated(address newReceiver);
    event LpTokenWhitelisted(address indexed lpToken, bool status);
    event WhitelistStatusChanged(bool enabled);

    constructor() Ownable(msg.sender) {
        feeReceiver = msg.sender;
    }

    /**
     * @notice Lock LP tokens for a specified duration
     * @param lpToken The LP token address to lock
     * @param amount The amount of LP tokens to lock
     * @param unlockDate The timestamp when tokens can be withdrawn
     * @param description Optional description for the lock
     * @return lockId The unique identifier for this lock
     */
    function lockLiquidity(
        address lpToken,
        uint256 amount,
        uint256 unlockDate,
        string calldata description
    ) external nonReentrant returns (uint256 lockId) {
        require(lpToken != address(0), "Invalid LP token address");
        require(amount > 0, "Amount must be greater than 0");
        require(unlockDate > block.timestamp, "Unlock date must be in the future");

        if (whitelistEnabled) {
            require(whitelistedLpTokens[lpToken], "LP token not whitelisted");
        }

        IERC20 lpTokenContract = IERC20(lpToken);
        uint256 balanceBefore = lpTokenContract.balanceOf(address(this));

        // Transfer LP tokens to this contract
        lpTokenContract.safeTransferFrom(msg.sender, address(this), amount);

        uint256 balanceAfter = lpTokenContract.balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;

        // Calculate fee
        uint256 feeAmount = 0;
        if (lockFee > 0) {
            feeAmount = (actualAmount * lockFee) / 10000;
            if (feeAmount > 0) {
                lpTokenContract.safeTransfer(feeReceiver, feeAmount);
                actualAmount -= feeAmount;
            }
        }

        require(actualAmount > 0, "Amount after fee must be greater than 0");

        // Create lock
        lockId = lockIdCounter++;
        locks[lockId] = LiquidityLock({
            lockId: lockId,
            lpToken: lpToken,
            owner: msg.sender,
            amount: actualAmount,
            lockDate: block.timestamp,
            unlockDate: unlockDate,
            description: description,
            withdrawn: false,
            isVesting: false,
            vestingStartDate: 0,
            vestingEndDate: 0,
            totalVestingAmount: 0,
            withdrawnAmount: 0
        });

        userLockIds[msg.sender].push(lockId);
        lpTokenLockIds[lpToken].push(lockId);

        emit LiquidityLocked(lockId, lpToken, msg.sender, actualAmount, unlockDate, description, false);
    }

    /**
     * @notice Lock LP tokens with vesting schedule
     * @param lpToken The LP token address to lock
     * @param amount The amount of LP tokens to lock
     * @param vestingStartDate When vesting begins
     * @param vestingEndDate When vesting ends
     * @param description Optional description for the lock
     * @return lockId The unique identifier for this lock
     */
    function lockLiquidityWithVesting(
        address lpToken,
        uint256 amount,
        uint256 vestingStartDate,
        uint256 vestingEndDate,
        string calldata description
    ) external nonReentrant returns (uint256 lockId) {
        require(lpToken != address(0), "Invalid LP token address");
        require(amount > 0, "Amount must be greater than 0");
        require(vestingStartDate >= block.timestamp, "Vesting start must be now or future");
        require(vestingEndDate > vestingStartDate, "Vesting end must be after start");

        if (whitelistEnabled) {
            require(whitelistedLpTokens[lpToken], "LP token not whitelisted");
        }

        IERC20 lpTokenContract = IERC20(lpToken);
        uint256 balanceBefore = lpTokenContract.balanceOf(address(this));

        lpTokenContract.safeTransferFrom(msg.sender, address(this), amount);

        uint256 balanceAfter = lpTokenContract.balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;

        // Calculate fee
        uint256 feeAmount = 0;
        if (lockFee > 0) {
            feeAmount = (actualAmount * lockFee) / 10000;
            if (feeAmount > 0) {
                lpTokenContract.safeTransfer(feeReceiver, feeAmount);
                actualAmount -= feeAmount;
            }
        }

        require(actualAmount > 0, "Amount after fee must be greater than 0");

        lockId = lockIdCounter++;
        locks[lockId] = LiquidityLock({
            lockId: lockId,
            lpToken: lpToken,
            owner: msg.sender,
            amount: actualAmount,
            lockDate: block.timestamp,
            unlockDate: vestingEndDate,
            description: description,
            withdrawn: false,
            isVesting: true,
            vestingStartDate: vestingStartDate,
            vestingEndDate: vestingEndDate,
            totalVestingAmount: actualAmount,
            withdrawnAmount: 0
        });

        userLockIds[msg.sender].push(lockId);
        lpTokenLockIds[lpToken].push(lockId);

        emit LiquidityLocked(lockId, lpToken, msg.sender, actualAmount, vestingEndDate, description, true);
    }

    /**
     * @notice Withdraw LP tokens from a lock after unlock date
     * @param lockId The lock ID to withdraw from
     */
    function withdrawLiquidity(uint256 lockId) external nonReentrant {
        LiquidityLock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "Not lock owner");
        require(!lock.withdrawn, "Already withdrawn");
        require(!lock.isVesting, "Use claimVesting for vesting locks");
        require(block.timestamp >= lock.unlockDate, "Lock period not expired");

        lock.withdrawn = true;

        IERC20(lock.lpToken).safeTransfer(msg.sender, lock.amount);

        emit LiquidityWithdrawn(lockId, lock.lpToken, msg.sender, lock.amount);
    }

    /**
     * @notice Claim vested tokens from a vesting lock
     * @param lockId The lock ID to claim from
     */
    function claimVesting(uint256 lockId) external nonReentrant {
        LiquidityLock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "Not lock owner");
        require(lock.isVesting, "Not a vesting lock");
        require(block.timestamp >= lock.vestingStartDate, "Vesting not started");

        uint256 claimableAmount = getClaimableAmount(lockId);
        require(claimableAmount > 0, "No tokens available to claim");

        lock.withdrawnAmount += claimableAmount;
        lock.amount -= claimableAmount;

        if (block.timestamp >= lock.vestingEndDate) {
            lock.withdrawn = true;
        }

        IERC20(lock.lpToken).safeTransfer(msg.sender, claimableAmount);

        emit VestingClaimed(lockId, msg.sender, claimableAmount, lock.withdrawnAmount);
    }

    /**
     * @notice Get the claimable amount for a vesting lock
     * @param lockId The lock ID
     * @return The amount that can be claimed
     */
    function getClaimableAmount(uint256 lockId) public view returns (uint256) {
        LiquidityLock storage lock = locks[lockId];

        if (!lock.isVesting) {
            return 0;
        }

        if (block.timestamp < lock.vestingStartDate) {
            return 0;
        }

        if (block.timestamp >= lock.vestingEndDate) {
            return lock.amount;
        }

        uint256 vestingDuration = lock.vestingEndDate - lock.vestingStartDate;
        uint256 elapsedTime = block.timestamp - lock.vestingStartDate;
        uint256 vestedAmount = (lock.totalVestingAmount * elapsedTime) / vestingDuration;

        return vestedAmount - lock.withdrawnAmount;
    }

    /**
     * @notice Extend the unlock date of a lock
     * @param lockId The lock ID to extend
     * @param newUnlockDate The new unlock date (must be later than current)
     */
    function extendLock(uint256 lockId, uint256 newUnlockDate) external {
        LiquidityLock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "Not lock owner");
        require(!lock.withdrawn, "Already withdrawn");
        require(newUnlockDate > lock.unlockDate, "New unlock date must be later");

        uint256 oldUnlockDate = lock.unlockDate;
        lock.unlockDate = newUnlockDate;

        if (lock.isVesting) {
            lock.vestingEndDate = newUnlockDate;
        }

        emit LockExtended(lockId, oldUnlockDate, newUnlockDate);
    }

    /**
     * @notice Increase the amount of LP tokens in an existing lock
     * @param lockId The lock ID to add tokens to
     * @param additionalAmount The amount of tokens to add
     */
    function increaseLockAmount(uint256 lockId, uint256 additionalAmount) external nonReentrant {
        LiquidityLock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "Not lock owner");
        require(!lock.withdrawn, "Already withdrawn");
        require(additionalAmount > 0, "Amount must be greater than 0");

        IERC20 lpTokenContract = IERC20(lock.lpToken);
        uint256 balanceBefore = lpTokenContract.balanceOf(address(this));

        lpTokenContract.safeTransferFrom(msg.sender, address(this), additionalAmount);

        uint256 balanceAfter = lpTokenContract.balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;

        // Calculate fee
        uint256 feeAmount = 0;
        if (lockFee > 0) {
            feeAmount = (actualAmount * lockFee) / 10000;
            if (feeAmount > 0) {
                lpTokenContract.safeTransfer(feeReceiver, feeAmount);
                actualAmount -= feeAmount;
            }
        }

        require(actualAmount > 0, "Amount after fee must be greater than 0");

        uint256 oldAmount = lock.amount;
        lock.amount += actualAmount;

        if (lock.isVesting) {
            lock.totalVestingAmount += actualAmount;
        }

        emit LockAmountIncreased(lockId, oldAmount, lock.amount);
    }

    /**
     * @notice Split a lock into two separate locks
     * @param lockId The lock ID to split
     * @param splitAmount The amount to move to the new lock
     * @return newLockId The ID of the newly created lock
     */
    function splitLock(uint256 lockId, uint256 splitAmount) external nonReentrant returns (uint256 newLockId) {
        LiquidityLock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "Not lock owner");
        require(!lock.withdrawn, "Already withdrawn");
        require(!lock.isVesting, "Cannot split vesting locks");
        require(splitAmount > 0 && splitAmount < lock.amount, "Invalid split amount");

        uint256 remainingAmount = lock.amount - splitAmount;
        lock.amount = remainingAmount;

        // Create new lock with split amount
        newLockId = lockIdCounter++;
        locks[newLockId] = LiquidityLock({
            lockId: newLockId,
            lpToken: lock.lpToken,
            owner: msg.sender,
            amount: splitAmount,
            lockDate: block.timestamp,
            unlockDate: lock.unlockDate,
            description: lock.description,
            withdrawn: false,
            isVesting: false,
            vestingStartDate: 0,
            vestingEndDate: 0,
            totalVestingAmount: 0,
            withdrawnAmount: 0
        });

        userLockIds[msg.sender].push(newLockId);
        lpTokenLockIds[lock.lpToken].push(newLockId);

        emit LockSplit(lockId, newLockId, remainingAmount, splitAmount);
    }

    /**
     * @notice Transfer lock ownership to another address
     * @param lockId The lock ID to transfer
     * @param newOwner The new owner address
     */
    function transferLockOwnership(uint256 lockId, address newOwner) external {
        LiquidityLock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "Not lock owner");
        require(newOwner != address(0), "Invalid new owner");
        require(!lock.withdrawn, "Already withdrawn");

        address oldOwner = lock.owner;
        lock.owner = newOwner;

        userLockIds[newOwner].push(lockId);

        emit LockOwnershipTransferred(lockId, oldOwner, newOwner);
    }

    /**
     * @notice Get all lock IDs for a user
     * @param user The user address
     * @return Array of lock IDs
     */
    function getUserLockIds(address user) external view returns (uint256[] memory) {
        return userLockIds[user];
    }

    /**
     * @notice Get all lock IDs for an LP token
     * @param lpToken The LP token address
     * @return Array of lock IDs
     */
    function getLpTokenLockIds(address lpToken) external view returns (uint256[] memory) {
        return lpTokenLockIds[lpToken];
    }

    /**
     * @notice Get lock details
     * @param lockId The lock ID
     * @return Lock details
     */
    function getLock(uint256 lockId) external view returns (LiquidityLock memory) {
        return locks[lockId];
    }

    /**
     * @notice Get multiple locks by IDs
     * @param lockIds Array of lock IDs
     * @return Array of lock details
     */
    function getMultipleLocks(uint256[] calldata lockIds) external view returns (LiquidityLock[] memory) {
        LiquidityLock[] memory result = new LiquidityLock[](lockIds.length);
        for (uint256 i = 0; i < lockIds.length; i++) {
            result[i] = locks[lockIds[i]];
        }
        return result;
    }

    /**
     * @notice Get total locked amount for an LP token
     * @param lpToken The LP token address
     * @return Total amount locked
     */
    function getTotalLockedAmount(address lpToken) external view returns (uint256) {
        uint256[] memory lockIds = lpTokenLockIds[lpToken];
        uint256 total = 0;

        for (uint256 i = 0; i < lockIds.length; i++) {
            LiquidityLock storage lock = locks[lockIds[i]];
            if (!lock.withdrawn) {
                total += lock.amount;
            }
        }

        return total;
    }

    /**
     * @notice Update the lock fee (only owner)
     * @param newFee The new fee in basis points (100 = 1%)
     */
    function setLockFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee cannot exceed 10%");
        lockFee = newFee;
        emit FeeUpdated(newFee);
    }

    /**
     * @notice Update the fee receiver address (only owner)
     * @param newReceiver The new fee receiver address
     */
    function setFeeReceiver(address newReceiver) external onlyOwner {
        require(newReceiver != address(0), "Invalid receiver address");
        feeReceiver = newReceiver;
        emit FeeReceiverUpdated(newReceiver);
    }

    /**
     * @notice Whitelist or blacklist an LP token (only owner)
     * @param lpToken The LP token address
     * @param status True to whitelist, false to blacklist
     */
    function setLpTokenWhitelist(address lpToken, bool status) external onlyOwner {
        whitelistedLpTokens[lpToken] = status;
        emit LpTokenWhitelisted(lpToken, status);
    }

    /**
     * @notice Enable or disable whitelist requirement (only owner)
     * @param enabled True to enable whitelist, false to disable
     */
    function setWhitelistEnabled(bool enabled) external onlyOwner {
        whitelistEnabled = enabled;
        emit WhitelistStatusChanged(enabled);
    }
}
