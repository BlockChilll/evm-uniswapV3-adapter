// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FixedPoint96} from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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

    uint256 private constant PRICE_PRECISION = 10 ** 18;
    uint32 private constant TWAP_INTERVAL = 600; // 10 minutes
    uint224 private constant SLIPPAGE_MAX = 10_000; // 10,000 basis points = 100%

    IQuoterV2 public immutable i_quoter;
    ISwapRouter public immutable i_swapRouter;
    IUniswapV3Factory public immutable i_factory;
    INonfungiblePositionManager public immutable i_nonfungiblePositionManager;

    constructor(address _factory, address _nonfungiblePositionManager, address _swapRouter, address _quoter) {
        i_quoter = IQuoterV2(_quoter);
        i_factory = IUniswapV3Factory(_factory);
        i_swapRouter = ISwapRouter(_swapRouter);
        i_nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
    }

    /**
     * @notice Get the pool address for a given pair of tokens and fee
     * @param tokenA The first token of the pair
     * @param tokenB The second token of the pair
     * @param fee The fee of the pool
     * @return pool The address of the pool
     */
    function getPoolAddress(address tokenA, address tokenB, uint24 fee) public view returns (address pool) {
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

    /**
     * @notice Get the price of a token in the other token
     * @param tokenIn The token being priced
     * @param tokenOut The token being priced against
     * @param fee The fee of the pool
     * @return price The price of the token in 18 decimals
     */
    function getPrice(address tokenIn, address tokenOut, uint24 fee) external view returns (uint256 price) {
        address pool = getPoolAddress(tokenIn, tokenOut, fee);

        uint32 oldestObservationSecondsAgo = OracleLibrary.getOldestObservationSecondsAgo(pool);

        int24 priceTick;

        if (oldestObservationSecondsAgo < TWAP_INTERVAL) {
            (, priceTick,,,,,) = IUniswapV3Pool(pool).slot0();
        } else {
            (priceTick,) = OracleLibrary.consult(pool, TWAP_INTERVAL);
        }

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(priceTick);

        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);

        uint256 tokenInDecimals = IERC20Metadata(tokenIn).decimals();
        uint256 tokenOutDecimals = IERC20Metadata(tokenOut).decimals();

        // price = token1 * 10 ** token1Decimals / token0 * 10 ** token0Decimals
        if (tokenIn < tokenOut) {
            // tokenIn is token0
            price = FullMath.mulDiv(
                priceX96, PRICE_PRECISION * (10 ** tokenInDecimals), FixedPoint96.Q96 * (10 ** tokenOutDecimals)
            );
        } else {
            // tokenIn is token1
            price = FullMath.mulDiv(
                PRICE_PRECISION * (10 ** tokenInDecimals), FixedPoint96.Q96, priceX96 * (10 ** tokenOutDecimals)
            );
        }
    }
}
