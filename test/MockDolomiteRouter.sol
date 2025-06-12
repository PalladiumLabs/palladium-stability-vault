pragma solidity ^0.8.0;

import "../src/strategies/interfaces/IDepositWithdrawalRouter.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract MockDolomiteRouter is IDepositWithdrawalRouter {
    mapping(uint256 => address) public mrkt;
    mapping(address => uint256) public balance;

    function setMarket(uint256 _marketId, address _token) external {
        mrkt[_marketId] = _token;
    }

    function depositWei(
        uint256 _isolationModeMarketId,
        uint256 _toAccountNumber,
        uint256 _marketId,
        uint256 _amountWei,
        EventFlag _eventFlag
    ) external {
        address token = mrkt[_marketId];
        IERC20(token).transferFrom(msg.sender, address(this), _amountWei);
    }

    function withdrawWei(
        uint256 _isolationModeMarketId,
        uint256 _fromAccountNumber,
        uint256 _marketId,
        uint256 _amountWei,
        AccountBalanceLib.BalanceCheckFlag _balanceCheckFlag
    ) external {
        address token = mrkt[_marketId];
        IERC20(token).transfer(msg.sender, _amountWei);
    }
}
