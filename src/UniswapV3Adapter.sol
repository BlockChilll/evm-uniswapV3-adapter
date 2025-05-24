// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {IUniswapV3Adapter} from "./interfaces/IUniswapV3Adapter.sol";

/**
 * @title UniswapV3Adapter
 * @author @denissosnowsky
 * @notice This contract is used to interact with the Uniswap V3 protocol.
 * It is used to swap tokens, add liquidity, and remove liquidity.
 */
contract UniswapV3Adapter is IUniswapV3Adapter {
    error SlippageTooHigh(uint256 slippage);

    uint256 private constant SLIPPAGE_MAX = 10_000; // 10,000 basis points = 100%

    IUniswapV3Factory public immutable i_factory;
    ISwapRouter public immutable i_swapRouter;
    INonfungiblePositionManager public immutable i_nonfungiblePositionManager;
    IQuoterV2 public immutable i_quoter;

    constructor(address _factory, address _nonfungiblePositionManager, address _swapRouter, address _quoter) {
        i_factory = IUniswapV3Factory(_factory);
        i_nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        i_swapRouter = ISwapRouter(_swapRouter);
        i_quoter = IQuoterV2(_quoter);
    }

    /**
     * @notice Get the pool address for a given pair of tokens and fee
     * @param tokenA The first token of the pair
     * @param tokenB The second token of the pair
     * @param fee The fee of the pool
     * @return pool The address of the pool
     */
    function getPoolAddress(address tokenA, address tokenB, uint24 fee) external view returns (address pool) {
        pool = i_factory.getPool(tokenA, tokenB, fee);
    }

    /**
     * @notice Get the expected amount out for a swap
     * @param tokenIn The token being swapped in
     * @param tokenOut The token being swapped out
     * @param amountIn The amount of tokens being swapped in
     * @param fee The fee of the pool
     * @return amountOut The expected amount out
     * @dev This function should be called via staticcall
     */
    function getExpectedAmountOut(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee)
        external
        returns (uint256)
    {
        (uint256 amountOut,,,) = IQuoterV2(i_quoter).quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                fee: fee,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                sqrtPriceLimitX96: 0
            })
        );

        return amountOut;
    }
}
