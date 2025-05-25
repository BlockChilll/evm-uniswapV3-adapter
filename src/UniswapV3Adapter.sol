// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
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
    uint256 private constant Q96 = 0x1000000000000000000000000;

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
     * @notice Add liquidity to a pool
     * @param params The parameters for the add liquidity transaction
     * @notice allows deposit tokens in any order
     * @notice allows to set prices instead of ticks, prices must be token0 in token 1, in 18 decimals
     */
    function addLiquidity(AddLiquidityParams memory params) external returns (uint256 amount0, uint256 amount1) {
        int24 tickSpacing = IUniswapV3Pool(getPoolAddress(params.token0, params.token1, params.fee)).tickSpacing();

        (address token0, address token1) =
            params.token0 < params.token1 ? (params.token0, params.token1) : (params.token1, params.token0);
        (uint128 amount0Desired, uint128 amount1Desired) = params.token0 < params.token1
            ? (params.amount0Desired, params.amount1Desired)
            : (params.amount1Desired, params.amount0Desired);
        (uint128 amount0Min, uint128 amount1Min) = params.token0 < params.token1
            ? (params.amount0Min, params.amount1Min)
            : (params.amount1Min, params.amount0Min);

        uint256 token0Decimals = IERC20Metadata(token0).decimals();
        uint256 token1Decimals = IERC20Metadata(token1).decimals();

        // price = token1 * 10 ** token1Decimals / token0 * 10 ** token0Decimals
        uint256 priceLowerQ96;
        uint256 priceUpperQ96;
        /**
         * Because token order in params can be any order, we need to handle both cases
         * params.token0 is token0 and params.token1 is token1
         * params.token0 is token1 and params.token1 is token0
         * It defines in which order to multiply the price decimals, and which price is lower and upper in accordance with the token order
         */
        if (params.token0 < params.token1) {
            uint256 priceDecimalsNominator = 10 ** token1Decimals;
            uint256 priceDecimalsDenominator = (10 ** token0Decimals) * PRICE_PRECISION;
            priceLowerQ96 =
                FullMath.mulDiv(params.priceLower * Q96, priceDecimalsNominator, priceDecimalsDenominator);
            priceUpperQ96 =
                FullMath.mulDiv(params.priceUpper * Q96, priceDecimalsNominator, priceDecimalsDenominator);
        } else {
            uint256 priceDecimalsNominator = 10 ** token1Decimals * PRICE_PRECISION;
            uint256 priceDecimalsDenominator = (10 ** token0Decimals);
            priceUpperQ96 =
                FullMath.mulDiv(Q96, priceDecimalsNominator, params.priceLower * priceDecimalsDenominator);
            priceLowerQ96 =
                FullMath.mulDiv(Q96, priceDecimalsNominator, params.priceUpper * priceDecimalsDenominator);
        }

        uint256 priceLowerQ192 = priceLowerQ96 * Q96;
        uint256 priceLowerSqrtX96 = Math.sqrt(priceLowerQ192);

        uint256 priceUpperQ192 = priceUpperQ96 * Q96;
        uint256 priceUpperSqrtX96 = Math.sqrt(priceUpperQ192);

        int24 tickLower = TickMath.getTickAtSqrtRatio(uint160(priceLowerSqrtX96));
        int24 tickUpper = TickMath.getTickAtSqrtRatio(uint160(priceUpperSqrtX96));

        int24 tickLowerAligned = alignTickToSpacing(tickLower, tickSpacing, false);
        int24 tickUpperAligned = alignTickToSpacing(tickUpper, tickSpacing, true);

        IERC20(token0).transferFrom(msg.sender, address(this), amount0Desired);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1Desired);

        IERC20(token0).approve(address(i_nonfungiblePositionManager), amount0Desired);
        IERC20(token1).approve(address(i_nonfungiblePositionManager), amount1Desired);

        (,, amount0, amount1) = INonfungiblePositionManager(i_nonfungiblePositionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: params.fee,
                tickLower: tickLowerAligned,
                tickUpper: tickUpperAligned,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: msg.sender,
                deadline: params.deadline
            })
        );

        if (amount0Desired > amount0) {
            IERC20(token0).transfer(msg.sender, amount0Desired - amount0);
        }

        if (amount1Desired > amount1) {
            IERC20(token1).transfer(msg.sender, amount1Desired - amount1);
        }

        (amount0, amount1) = params.token0 < params.token1 ? (amount0, amount1) : (amount1, amount0);
    }

    /**
     * @notice Increase liquidity to a position
     * @param params The parameters for the increase liquidity transaction
     * @notice allows increase liquidity in any order
     * Amount order is defined by token0 and token1 order in params
     */
    function increaseLiquidity(IncreaseLiquidityParams memory params)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        (address token0, address token1) =
            params.token0 < params.token1 ? (params.token0, params.token1) : (params.token1, params.token0);
        (uint256 amount0Desired, uint256 amount1Desired) = params.token0 < params.token1
            ? (params.amount0Desired, params.amount1Desired)
            : (params.amount1Desired, params.amount0Desired);
        (uint256 amount0Min, uint256 amount1Min) = params.token0 < params.token1
            ? (params.amount0Min, params.amount1Min)
            : (params.amount1Min, params.amount0Min);

        IERC20(token0).transferFrom(msg.sender, address(this), amount0Desired);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1Desired);

        IERC20(token0).approve(address(i_nonfungiblePositionManager), amount0Desired);
        IERC20(token1).approve(address(i_nonfungiblePositionManager), amount1Desired);

        (, amount0, amount1) = INonfungiblePositionManager(i_nonfungiblePositionManager).increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: params.tokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: params.deadline
            })
        );

        if (amount0Desired > amount0) {
            IERC20(token0).transfer(msg.sender, amount0Desired - amount0);
        }

        if (amount1Desired > amount1) {
            IERC20(token1).transfer(msg.sender, amount1Desired - amount1);
        }

        (amount0, amount1) = params.token0 < params.token1 ? (amount0, amount1) : (amount1, amount0);
    }

    /**
     * @notice Decrease liquidity from a position
     * @param params The parameters for the decrease liquidity transaction
     * @notice allows decrease liquidity in any order
     * Amount min order is defined by token0 and token1 order in params
     * @notice position tokenId should be approved to spend by current contract from msg.sender
     */
    function decreaseLiquidity(DecreaseLiquidityParams memory params)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        (uint256 amount0Min, uint256 amount1Min) = params.token0 < params.token1
            ? (params.amount0Min, params.amount1Min)
            : (params.amount1Min, params.amount0Min);

        (amount0, amount1) = INonfungiblePositionManager(i_nonfungiblePositionManager).decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: params.tokenId,
                liquidity: params.liquidity,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: params.deadline
            })
        );

        (amount0, amount1) = params.token0 < params.token1 ? (amount0, amount1) : (amount1, amount0);
    }

    /**
     * @notice Collect fees from a position
     * @param params The parameters for the collect transaction
     * @notice allows collect fees in any order
     * Amount max order is defined by token0 and token1 order in params
     * @notice position tokenId should be approved to spend by current contract from msg.sender
     * @return amount0 The amount collected in token0
     * @return amount1 The amount collected in token1
     */
    function collect(CollectParams memory params) external returns (uint256 amount0, uint256 amount1) {
        (uint128 amount0Max, uint128 amount1Max) = params.token0 < params.token1
            ? (params.amount0Max, params.amount1Max)
            : (params.amount1Max, params.amount0Max);

        (amount0, amount1) = INonfungiblePositionManager(i_nonfungiblePositionManager).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: params.tokenId,
                recipient: msg.sender,
                amount0Max: amount0Max,
                amount1Max: amount1Max
            })
        );

        (amount0, amount1) = params.token0 < params.token1 ? (amount0, amount1) : (amount1, amount0);
    }

    /**
     * @notice Swap a single token for another token
     * @param params The parameters for the swap
     * @return amountOut The amount of the received token
     * @notice sender should approve the amount of tokenIn to this contract
     */
    function swapSingle(SwapSingleParams memory params) external returns (uint256 amountOut) {
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        IERC20(params.tokenIn).approve(address(i_swapRouter), params.amountIn);

        amountOut = i_swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                fee: params.fee,
                recipient: params.recipient,
                deadline: params.deadline,
                amountIn: params.amountIn,
                amountOutMinimum: params.amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /// Getters

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

        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        uint256 tokenInDecimals = IERC20Metadata(tokenIn).decimals();
        uint256 tokenOutDecimals = IERC20Metadata(tokenOut).decimals();

        // price = token1 * 10 ** token1Decimals / token0 * 10 ** token0Decimals
        if (tokenIn < tokenOut) {
            // tokenIn is token0
            price = FullMath.mulDiv(
                priceX96, PRICE_PRECISION * (10 ** tokenInDecimals), Q96 * (10 ** tokenOutDecimals)
            );
        } else {
            // tokenIn is token1
            price = FullMath.mulDiv(
                PRICE_PRECISION * (10 ** tokenInDecimals), Q96, priceX96 * (10 ** tokenOutDecimals)
            );
        }
    }

    /**
     * @notice Get the pool info
     * @param pool The address of the pool
     * @return fee The fee of the pool
     * @return token0 The first token of the pool
     * @return token1 The second token of the pool
     * @return tick The current tick of the pool
     * @return sqrtPriceX96 The current sqrt price of the pool
     */
    function getPoolInfo(address pool)
        external
        view
        returns (uint24 fee, address token0, address token1, int24 tick, uint160 sqrtPriceX96)
    {
        (sqrtPriceX96, tick,,,,,) = IUniswapV3Pool(pool).slot0();
        fee = IUniswapV3Pool(pool).fee();
        token0 = IUniswapV3Pool(pool).token0();
        token1 = IUniswapV3Pool(pool).token1();
    }

    /**
     * @notice Get the positions of a user
     * @param user The address of the user
     * @return positions The positions of the user
     */
    function getUserPositions(address user) external view returns (Position[] memory positions) {
        uint256 userBalance = INonfungiblePositionManager(i_nonfungiblePositionManager).balanceOf(user);

        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;

        positions = new Position[](userBalance);

        for (uint256 i = 0; i < userBalance; i++) {
            uint256 tokenId = INonfungiblePositionManager(i_nonfungiblePositionManager).tokenOfOwnerByIndex(user, i);

            (,, token0, token1, fee, tickLower, tickUpper, liquidity,,,,) =
                INonfungiblePositionManager(i_nonfungiblePositionManager).positions(tokenId);
            positions[i] = Position({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidity: liquidity,
                tokenId: tokenId
            });
        }
    }

    /**
     * @notice Align a tick to the nearest tick spacing
     * @param tick The tick to align
     * @param tickSpacing The tick spacing
     * @param upper Whether to round up or down
     * @return alignedTick The aligned tick
     */
    function alignTickToSpacing(int24 tick, int24 tickSpacing, bool upper) internal pure returns (int24) {
        if (upper) {
            return ((tick + tickSpacing - 1) / tickSpacing) * tickSpacing;
        } else {
            return (tick / tickSpacing) * tickSpacing;
        }
    }
}
