pragma solidity ^0.8.0;

import "../src/strategies/interfaces/IDolomiteMargin.sol";
import "./MockDolomiteRouter.sol";

import "@openzeppelin/token/ERC20/IERC20.sol";

contract MockDolomiteMargin is IDolomiteMargin {
    address public dolomiteRouter;
    mapping(address => uint256) public marketIdByTokenAddress;

    constructor(address _dolomiteRouter) {
        dolomiteRouter = _dolomiteRouter;
    }

    function setMarketIdByTokenAddress(address token, uint256 marketId) external {
        marketIdByTokenAddress[token] = marketId;
    }

    function getMarketIdByTokenAddress(address token) external view returns (uint256) {
        return marketIdByTokenAddress[token];
    }

    function getAccountWei(Account.Info calldata account, uint256 marketId) external view returns (Types.Wei memory) {
        uint256 balance = MockDolomiteRouter(dolomiteRouter).balance(account.owner);
        Types.Wei memory weiBalance;
        weiBalance.value = uint128(balance);
        weiBalance.sign = true; // Assuming positive balance for simplicity
        return weiBalance;
    }
}
