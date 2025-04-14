// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import "./StabilityVault.sol";

struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
}

contract MockRouter is Ownable {
    event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    function exactInputSingle(ExactInputSingleParams memory _params) external returns (uint256 amountOut) {
        IERC20(_params.tokenIn).transferFrom(msg.sender, address(this), _params.amountIn);
        IERC20(_params.tokenOut).transfer(_params.recipient, _params.amountOutMinimum);
        emit Swap(_params.tokenIn, _params.tokenOut, _params.amountIn, _params.amountOutMinimum);

        return _params.amountOutMinimum;
    }

    function withdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(msg.sender, _amount);
    }
}
