// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IUniswapV3Adapter {
    function getPoolAddress(address tokenA, address tokenB, uint24 fee) external view returns (address pool);

    function getExpectedAmountOut(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee)
        external
        returns (uint256);
}
