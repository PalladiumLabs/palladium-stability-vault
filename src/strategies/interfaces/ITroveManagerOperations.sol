// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface TroveManagerOperations {
    // Functions --------------------------------------------------------------------------------------------------------

    function liquidate(address _asset, address _borrower) external;

    function liquidateTroves(address _asset, uint256 _n) external;

    function computeNominalCR(uint256 _coll, uint256 _debt) external returns (uint256);
}
