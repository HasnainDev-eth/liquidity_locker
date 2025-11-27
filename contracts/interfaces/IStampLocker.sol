// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStampLocker
 * @notice Interface for StampLocker contracts
 */
interface IStampLocker {
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

    function lockTokens(
        address token,
        uint256 amount,
        uint256 unlockDate,
        string calldata description
    ) external returns (uint256 lockId);

    function withdrawTokens(uint256 lockId) external;

    function extendLock(uint256 lockId, uint256 newUnlockDate) external;

    function transferLockOwnership(uint256 lockId, address newOwner) external;

    function getUserLockIds(address user) external view returns (uint256[] memory);

    function getLock(uint256 lockId) external view returns (TokenLock memory);
}
