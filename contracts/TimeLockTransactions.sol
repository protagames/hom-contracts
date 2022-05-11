// SPDX-License-Identifier: NOLICENSE

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

contract TimeLockTransactions is Ownable {
    mapping (address => uint) private walletToTime;

    uint private constant MAX_ALLOWED_TIME = 1 days;
    uint private _lockTime = 5 minutes; // 5 minutes is the default

    // @dev unlock manually a wallet for one transaction
    // @note if you are inheriting this contract, you should expose this function and protect it via onlyowner or roles
    function _unlockWallet(address wallet) internal {
        walletToTime[wallet] = 0;
        emit UnlockedWallet(wallet);
    }
    event UnlockedWallet(address wallet);

    function getLockTime() external view returns(uint){
        return _lockTime;
    }

    function getLockTime(address wallet) external view returns (uint) {
        return walletToTime[wallet];
    }

    function lockToOperate(address addr) internal {
        walletToTime[addr] = block.timestamp + _lockTime;
    }

    function canOperate(address addr) public view returns (bool){
        return walletToTime[addr] <= block.timestamp;
    }

    function lockIfCanOperateAndRevertIfNotAllowed(address addr) internal {
        require(canOperate(addr), "TimeLock: the sender cannot operate yet");
        lockToOperate(addr);
    }

    function _setLockTime(uint timeBetweenTransactions) internal {
        require(timeBetweenTransactions <= MAX_ALLOWED_TIME, "TimeLock: max temp ban greater than the allowed");
        _lockTime = timeBetweenTransactions;
        emit SetLockTimeEvent(timeBetweenTransactions);
    }
    event SetLockTimeEvent(uint timeBetweenPurchases);

    function setLockTime(uint timeBetweenTransactions) external onlyOwner {
        _setLockTime(timeBetweenTransactions);
    }

    // @dev unlock a wallet for one transaction
    function unlockWallet(address wallet) external onlyOwner {
        _unlockWallet(wallet);
    }
}
