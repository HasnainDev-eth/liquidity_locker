// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title StampTokenLocker
 * @notice Locks ERC20 tokens for a specified duration, similar to UNCX Network
 * @dev Supports multiple locks per user, lock extensions, and ownership transfers
 */
contract StampTokenLocker is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct TokenLock {
        uint256 lockId;
        address token;
        address owner;
        uint256 amount;
        uint256 lockDate;
        uint256 unlockDate;
        string description;
        bool withdrawn;
    }

    // Lock ID counter
    uint256 public lockIdCounter;

    // Lock ID => Lock details
    mapping(uint256 => TokenLock) public locks;

    // User address => Lock IDs
    mapping(address => uint256[]) public userLockIds;

    // Token address => Lock IDs
    mapping(address => uint256[]) public tokenLockIds;

    // Fee settings (in basis points, 100 = 1%)
    uint256 public lockFee = 0; // Default 0%
    address public feeReceiver;

    // Events
    event TokensLocked(
        uint256 indexed lockId,
        address indexed token,
        address indexed owner,
        uint256 amount,
        uint256 unlockDate,
        string description
    );

    event TokensWithdrawn(
        uint256 indexed lockId,
        address indexed token,
        address indexed owner,
        uint256 amount
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

    event FeeUpdated(uint256 newFee);
    event FeeReceiverUpdated(address newReceiver);

    constructor() Ownable(msg.sender) {
        feeReceiver = msg.sender;
    }

    /**
     * @notice Lock ERC20 tokens for a specified duration
     * @param token The ERC20 token address to lock
     * @param amount The amount of tokens to lock
     * @param unlockDate The timestamp when tokens can be withdrawn
     * @param description Optional description for the lock
     * @return lockId The unique identifier for this lock
     */
    function lockTokens(
        address token,
        uint256 amount,
        uint256 unlockDate,
        string calldata description
    ) external nonReentrant returns (uint256 lockId) {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        require(unlockDate > block.timestamp, "Unlock date must be in the future");

        IERC20 tokenContract = IERC20(token);
        uint256 balanceBefore = tokenContract.balanceOf(address(this));

        // Transfer tokens to this contract
        tokenContract.safeTransferFrom(msg.sender, address(this), amount);

        uint256 balanceAfter = tokenContract.balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;

        // Calculate fee
        uint256 feeAmount = 0;
        if (lockFee > 0) {
            feeAmount = (actualAmount * lockFee) / 10000;
            if (feeAmount > 0) {
                tokenContract.safeTransfer(feeReceiver, feeAmount);
                actualAmount -= feeAmount;
            }
        }

        require(actualAmount > 0, "Amount after fee must be greater than 0");

        // Create lock
        lockId = lockIdCounter++;
        locks[lockId] = TokenLock({
            lockId: lockId,
            token: token,
            owner: msg.sender,
            amount: actualAmount,
            lockDate: block.timestamp,
            unlockDate: unlockDate,
            description: description,
            withdrawn: false
        });

        userLockIds[msg.sender].push(lockId);
        tokenLockIds[token].push(lockId);

        emit TokensLocked(lockId, token, msg.sender, actualAmount, unlockDate, description);
    }

    /**
     * @notice Withdraw tokens from a lock after unlock date
     * @param lockId The lock ID to withdraw from
     */
    function withdrawTokens(uint256 lockId) external nonReentrant {
        TokenLock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "Not lock owner");
        require(!lock.withdrawn, "Already withdrawn");
        require(block.timestamp >= lock.unlockDate, "Lock period not expired");

        lock.withdrawn = true;

        IERC20(lock.token).safeTransfer(msg.sender, lock.amount);

        emit TokensWithdrawn(lockId, lock.token, msg.sender, lock.amount);
    }

    /**
     * @notice Extend the unlock date of a lock
     * @param lockId The lock ID to extend
     * @param newUnlockDate The new unlock date (must be later than current)
     */
    function extendLock(uint256 lockId, uint256 newUnlockDate) external {
        TokenLock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "Not lock owner");
        require(!lock.withdrawn, "Already withdrawn");
        require(newUnlockDate > lock.unlockDate, "New unlock date must be later");

        uint256 oldUnlockDate = lock.unlockDate;
        lock.unlockDate = newUnlockDate;

        emit LockExtended(lockId, oldUnlockDate, newUnlockDate);
    }

    /**
     * @notice Increase the amount of tokens in an existing lock
     * @param lockId The lock ID to add tokens to
     * @param additionalAmount The amount of tokens to add
     */
    function increaseLockAmount(uint256 lockId, uint256 additionalAmount) external nonReentrant {
        TokenLock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "Not lock owner");
        require(!lock.withdrawn, "Already withdrawn");
        require(additionalAmount > 0, "Amount must be greater than 0");

        IERC20 tokenContract = IERC20(lock.token);
        uint256 balanceBefore = tokenContract.balanceOf(address(this));

        tokenContract.safeTransferFrom(msg.sender, address(this), additionalAmount);

        uint256 balanceAfter = tokenContract.balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;

        // Calculate fee
        uint256 feeAmount = 0;
        if (lockFee > 0) {
            feeAmount = (actualAmount * lockFee) / 10000;
            if (feeAmount > 0) {
                tokenContract.safeTransfer(feeReceiver, feeAmount);
                actualAmount -= feeAmount;
            }
        }

        require(actualAmount > 0, "Amount after fee must be greater than 0");

        uint256 oldAmount = lock.amount;
        lock.amount += actualAmount;

        emit LockAmountIncreased(lockId, oldAmount, lock.amount);
    }

    /**
     * @notice Transfer lock ownership to another address
     * @param lockId The lock ID to transfer
     * @param newOwner The new owner address
     */
    function transferLockOwnership(uint256 lockId, address newOwner) external {
        TokenLock storage lock = locks[lockId];
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
     * @notice Get all lock IDs for a token
     * @param token The token address
     * @return Array of lock IDs
     */
    function getTokenLockIds(address token) external view returns (uint256[] memory) {
        return tokenLockIds[token];
    }

    /**
     * @notice Get lock details
     * @param lockId The lock ID
     * @return Lock details
     */
    function getLock(uint256 lockId) external view returns (TokenLock memory) {
        return locks[lockId];
    }

    /**
     * @notice Get multiple locks by IDs
     * @param lockIds Array of lock IDs
     * @return Array of lock details
     */
    function getMultipleLocks(uint256[] calldata lockIds) external view returns (TokenLock[] memory) {
        TokenLock[] memory result = new TokenLock[](lockIds.length);
        for (uint256 i = 0; i < lockIds.length; i++) {
            result[i] = locks[lockIds[i]];
        }
        return result;
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
}
