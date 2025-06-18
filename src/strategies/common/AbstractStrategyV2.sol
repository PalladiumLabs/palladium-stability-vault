// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// import "@openzeppelin/access/Ownable2Step.sol";
import "../../../lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import "../../../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
// import "@openzeppelin/security/Pausable.sol";

abstract contract AbstractStrategyV2 is Ownable2StepUpgradeable, PausableUpgradeable {
    // common addresses for the strategy
    address public vault;
    address public router;
    address public manager;
    address private _pendingManager;

    event SetManager(address manager);

    //Modifier to restrict access to only vault
    function onlyVault() public view {
        require(msg.sender == vault, "!vault");
    }

    // checks that caller is either owner or manager.
    function onlyManager() public view {
        require(msg.sender == manager, "!manager");
    }

    function setManager(address _manager) external {
        onlyManager();
        require(_manager != address(0), "IA"); //invalid address
        _pendingManager = _manager;
        emit SetManager(_manager);
    }

    function renounceOwnership() public view override onlyOwner {
        revert("ROD"); //Renounce ownership disabled
    }

    function _transferManagership(address newManager) internal virtual {
        delete _pendingManager;
        manager = newManager;
        emit SetManager(newManager);
    }

    function acceptManagership() external {
        require(_pendingManager == msg.sender, "CINNM"); //Caller Is Not New Manager
        _transferManagership(msg.sender);
    }

    uint256[50] private __gap;
}
