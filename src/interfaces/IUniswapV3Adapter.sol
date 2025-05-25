// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IUniswapV3Adapter {
    struct Position {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 tokenId;
    }

    /**
     * @param token0 The first token of the pair
     * @param token1 The second token of the pair
     * @param fee The fee of the pool
     * @param priceLower The lower price in 18 decimals: token0 price in token1
     * @param priceUpper The upper price in 18 decimals: token0 price in token1
     * @param amount0Desired The amount of token0 to add
     * @param amount1Desired The amount of token1 to add
     * @param amount0Min The minimum amount of token0 to add
     * @param amount1Min The minimum amount of token1 to add
     * @param deadline The deadline for the transaction
     */
    struct AddLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        uint256 priceLower;
        uint256 priceUpper;
        uint128 amount0Desired;
        uint128 amount1Desired;
        uint128 amount0Min;
        uint128 amount1Min;
        uint256 deadline;
    }
    /**
     * @param tokenId The ID of the token for which liquidity is being increased
     * @param amount0Desired The desired amount of token0 to be spent
     * @param amount1Desired The desired amount of token1 to be spent
     * @param amount0Min The minimum amount of token0 to spend
     * @param amount1Min The minimum amount of token1 to spend
     * @param deadline The deadline for the transaction
     * @param token0 The first token of the pair
     * @param token1 The second token of the pair
     */

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
        address token0;
        address token1;
    }

    /**
     * @param tokenId The ID of the token for which liquidity is being decreased
     * @param liquidity The amount of liquidity to decrease
     * @param amount0Min The minimum amount of token0 to spend
     * @param amount1Min The minimum amount of token1 to spend
     * @param deadline The deadline for the transaction
     * @param token0 The first token of the pair
     * @param token1 The second token of the pair
     */
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
        address token0;
        address token1;
    }

    /**
     * @param tokenId The ID of the token for which tokens are being collected
     * @param recipient The account that should receive the tokens
     * @param amount0Max The maximum amount of token0 to collect
     * @param amount1Max The maximum amount of token1 to collect
     * @param token0 The first token of the pair
     * @param token1 The second token of the pair
     */
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
        address token0;
        address token1;
    }

    /**
     * @param tokenIn The token to swap from
     * @param tokenOut The token to swap to
     * @param fee The fee of the pool
     * @param recipient The account that should receive the tokens
     * @param deadline The deadline for the transaction
     * @param amountIn The amount of tokenIn to swap
     * @param amountOutMinimum The minimum amount of tokenOut to receive
     * @param sqrtPriceLimitX96 The limit on the price of the tokenIn
     */
    struct SwapSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /**
     * @param tokenA The first token of the pair
     * @param tokenB The second token of the pair
     * @param fee The fee of the pool
     * @return pool The address of the pool
     */
    function getPoolAddress(address tokenA, address tokenB, uint24 fee) external view returns (address pool);

    /**
     * @param tokenIn The token to swap from
     * @param tokenOut The token to swap to
     * @param amountIn The amount of tokenIn to swap
     * @param fee The fee of the pool
     * @return amountOut The expected amount of tokenOut
     */
    function getExpectedAmountOut(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee)
        external
        returns (uint256);

    /**
     * @param tokenIn The token to get the price of
     * @param tokenOut The token to get the price of
     * @param fee The fee of the pool
     * @return price The price of tokenIn in tokenOut
     */
    function getPrice(address tokenIn, address tokenOut, uint24 fee) external view returns (uint256 price);

    /**
     * @param pool The address of the pool
     * @return fee The fee of the pool
     * @return token0 The first token of the pair
     * @return token1 The second token of the pair
     * @return tick The current tick of the pool
     * @return sqrtPriceX96 The current sqrt price of the pool
     */
    function getPoolInfo(address pool)
        external
        view
        returns (uint24 fee, address token0, address token1, int24 tick, uint160 sqrtPriceX96);

    /**
     * @param user The address of the user
     * @return positions The positions of the user
     */
    function getUserPositions(address user) external view returns (Position[] memory positions);

    /**
     * @param params The parameters for the add liquidity transaction
     * @return amount0 The amount of token0 added
     * @return amount1 The amount of token1 added
     */
    function addLiquidity(AddLiquidityParams memory params) external returns (uint256 amount0, uint256 amount1);

    /**
     * @param params The parameters for the increase liquidity transaction
     * @return amount0 The amount of token0 added
     * @return amount1 The amount of token1 added
     */
    function increaseLiquidity(IncreaseLiquidityParams memory params)
        external
        returns (uint256 amount0, uint256 amount1);

    /**
     * @param params The parameters for the decrease liquidity transaction
     * @return amount0 The amount of token0 removed
     * @return amount1 The amount of token1 removed
     */
    function decreaseLiquidity(DecreaseLiquidityParams memory params)
        external
        returns (uint256 amount0, uint256 amount1);

    /**
     * @param params The parameters for the collect transaction
     * @return amount0 The amount of token0 collected
     * @return amount1 The amount of token1 collected
     */
    function collect(CollectParams memory params) external returns (uint256 amount0, uint256 amount1);

    /**
     * @param params The parameters for the swap single transaction
     * @return amountOut The amount of the received token
     */
    function swapSingle(SwapSingleParams memory params) external returns (uint256 amountOut);
}
