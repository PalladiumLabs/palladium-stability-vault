// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./AbstractStrategyV2.sol";

contract FeeManager is AbstractStrategyV2 {
    uint256 public withdrawFeeDecimals;
    uint256 public withdrawFee;

    uint256 public slippage;
    uint256 public slippageDecimals;

    uint256[50] private __gap;
}
