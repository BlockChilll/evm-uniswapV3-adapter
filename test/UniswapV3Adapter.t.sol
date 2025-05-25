// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {FixedPoint96} from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {UniswapV3Adapter} from "../src/UniswapV3Adapter.sol";
import {IUniswapV3Adapter} from "../src/interfaces/IUniswapV3Adapter.sol";

/**
 * Tests are run on EVM L1
 * token0 is USDC, token1 is WETH
 */
contract UniswapV3AdapterTest is Test {
    address public user = makeAddr("user");

    uint256 public constant USER_INITIAL_BALANCE = 10_000 ether;
    uint32 private constant TWAP_INTERVAL = 600; // 10 minutes

    // Mainnet information
    uint256 public BLOCK_NUMBER = 22554182;
    IUniswapV3Factory public factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IQuoterV2 public quoter = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    uint24 public USDC_WETH_FEE = 500;
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public USDC_WETH_500_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    IUniswapV3Adapter public adapter;

    function setUp() public {
        vm.createSelectFork("evm", BLOCK_NUMBER);
        adapter = new UniswapV3Adapter(
            address(factory), address(nonfungiblePositionManager), address(swapRouter), address(quoter)
        );

        vm.deal(user, USER_INITIAL_BALANCE);
        deal(USDC, user, USER_INITIAL_BALANCE);
        deal(WETH, user, USER_INITIAL_BALANCE);
    }

    function testGetPoolAddress() public view {
        address pool = adapter.getPoolAddress(USDC, WETH, USDC_WETH_FEE);
        assertEq(pool, USDC_WETH_500_POOL);
    }

    function testGetExpectedAmountOut() public {
        uint256 amountIn = 10_000 * 10 ** IERC20Metadata(USDC).decimals();

        (uint256 realAmountOut,,,) = IQuoterV2(quoter).quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                fee: USDC_WETH_FEE,
                tokenIn: USDC,
                tokenOut: WETH,
                amountIn: amountIn,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 amountOut = adapter.getExpectedAmountOut(USDC, WETH, amountIn, USDC_WETH_FEE);

        assertEq(amountOut, realAmountOut);
    }

    function testGetPrice() public view {
        // oldestObservationSecondsAgo in the testing block is 38424
        uint32 oldestObservationSecondsAgo = OracleLibrary.getOldestObservationSecondsAgo(USDC_WETH_500_POOL);
        assertEq(oldestObservationSecondsAgo, 38424);

        (int24 priceTick,) = OracleLibrary.consult(USDC_WETH_500_POOL, TWAP_INTERVAL);
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(priceTick);

        // testing block prices
        // price returned initially in 12 decimals
        uint256 priceOfUsdcInWeth = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 192) * 1e6; // 390606358000000 = 0.000390606358 WETH
        uint256 priceOfWethInUsdc = (1e18 * 1e18) / priceOfUsdcInWeth; //2560122178041966229336 = 2560.122178041966229336 USDC
        assertEq(priceOfUsdcInWeth, 0.000390606358 * 1e18);
        assertEq(priceOfWethInUsdc, 2560.122178041966229336 * 1e18);

        uint256 priceOfUsdcInWethAdapter = adapter.getPrice(USDC, WETH, USDC_WETH_FEE); // 390606358838339 = 0.000390606358 WETH
        uint256 priceOfWethInUsdcAdapter = adapter.getPrice(WETH, USDC, USDC_WETH_FEE); // 2560122172547301341251 = 2560.122172547301341251 USDC

        // compare firsts digits, as last digits can be different due to precision loss
        assertEq(priceOfUsdcInWethAdapter / 1e10, priceOfUsdcInWeth / 1e10);
        assertEq(priceOfWethInUsdcAdapter / 1e14, priceOfWethInUsdc / 1e14);
    }

    function testGetPoolInfo() public view {
        (uint160 sqrtPriceX96Real, int24 tickReal,,,,,) = IUniswapV3Pool(USDC_WETH_500_POOL).slot0();

        (uint24 fee, address token0, address token1, int24 tick, uint160 sqrtPriceX96) =
            adapter.getPoolInfo(USDC_WETH_500_POOL);
        assertEq(fee, USDC_WETH_FEE);
        assertEq(token0, USDC);
        assertEq(token1, WETH);
        assertEq(tick, tickReal);
        assertEq(sqrtPriceX96, sqrtPriceX96Real);
    }

    function testGetUserPositions() public {
        IUniswapV3Adapter.Position[] memory positions = adapter.getUserPositions(user);
        assertEq(positions.length, 0);

        vm.startPrank(user);
        IERC20(USDC).approve(address(nonfungiblePositionManager), 2 * 1e6);
        IERC20(WETH).approve(address(nonfungiblePositionManager), 2 * 1e18);
        INonfungiblePositionManager(nonfungiblePositionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: USDC,
                token1: WETH,
                fee: USDC_WETH_FEE,
                tickLower: -887240,
                tickUpper: 887240,
                amount0Desired: 1e6,
                amount1Desired: 1e18,
                amount0Min: 0,
                amount1Min: 0,
                recipient: user,
                deadline: block.timestamp + 1000
            })
        );
        INonfungiblePositionManager(nonfungiblePositionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: USDC,
                token1: WETH,
                fee: USDC_WETH_FEE,
                tickLower: -887240,
                tickUpper: 887240,
                amount0Desired: 1e6,
                amount1Desired: 1e18,
                amount0Min: 0,
                amount1Min: 0,
                recipient: user,
                deadline: block.timestamp + 1000
            })
        );
        vm.stopPrank();

        uint256 userBalance = INonfungiblePositionManager(nonfungiblePositionManager).balanceOf(user);
        assertEq(userBalance, 2);

        IUniswapV3Adapter.Position[] memory positionsAfter = adapter.getUserPositions(user);
        assertEq(positionsAfter.length, 2);
        assertEq(positionsAfter[0].token0, USDC);
        assertEq(positionsAfter[0].token1, WETH);
        assertEq(positionsAfter[0].fee, USDC_WETH_FEE);
        assertEq(positionsAfter[0].tickLower, -887240);
        assertEq(positionsAfter[0].tickUpper, 887240);

        assertEq(positionsAfter[1].token0, USDC);
        assertEq(positionsAfter[1].token1, WETH);
        assertEq(positionsAfter[1].fee, USDC_WETH_FEE);
        assertEq(positionsAfter[1].tickLower, -887240);
        assertEq(positionsAfter[1].tickUpper, 887240);
    }

    // price = token1 * 10 ** token1Decimals / token0 * 10 ** token0Decimals
    function testAddLiquidityInReverseOrderPrices() public {
        uint256 amountWETH = 1e18;
        uint256 amountUSDC = 1000e6;

        uint256 priceLowerToProvide = 2300 * 1e18;
        uint256 priceUpperToProvide = 2600 * 1e18;

        // test check by same price ticks and amounts in
        // ADAPTER deposit

        vm.startPrank(user);
        IERC20(WETH).approve(address(adapter), amountWETH);
        IERC20(USDC).approve(address(adapter), amountUSDC);

        (uint256 amount0, uint256 amount1) = adapter.addLiquidity(
            IUniswapV3Adapter.AddLiquidityParams({
                token0: WETH,
                token1: USDC,
                fee: USDC_WETH_FEE,
                priceLower: priceLowerToProvide,
                priceUpper: priceUpperToProvide,
                amount0Desired: uint128(amountWETH),
                amount1Desired: uint128(amountUSDC),
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1000
            })
        );

        IUniswapV3Adapter.Position[] memory positions = adapter.getUserPositions(user);
        assertEq(positions.length, 1);

        int24 tickLower = positions[0].tickLower; //197680
        int24 tickUpper = positions[0].tickUpper; //198920
        assertEq(tickLower, 197680);
        assertEq(tickUpper, 198920);

        uint160 sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(tickUpper);

        uint256 priceOfUsdcInWethLower = FullMath.mulDiv(sqrtPriceX96Lower, sqrtPriceX96Lower, 1 << 192) * 1e6; // 384329826000000 = 0.000384329826 WETH
        uint256 priceOfWethInUsdcLower = (1e18 * 1e18) / priceOfUsdcInWethLower; // 2601931810517354955428 = 2601.931810517354955428 USDC

        uint256 priceOfUsdcInWethUpper = FullMath.mulDiv(sqrtPriceX96Upper, sqrtPriceX96Upper, 1 << 192) * 1e6; // 435064766000000 = 0.000435064766 WETH
        uint256 priceOfWethInUsdcUpper = (1e18 * 1e18) / priceOfUsdcInWethUpper; // 2298508355880053040194 = 2298.508355880053040194 USDC

        assertApproxEqRel(priceLowerToProvide, priceOfWethInUsdcUpper, 1e18 * 5 / 100);
        assertApproxEqRel(priceUpperToProvide, priceOfWethInUsdcLower, 1e18 * 5 / 100);

        console.log("priceOfUsdcInWethLower", priceOfUsdcInWethLower);
        console.log("priceOfWethInUsdcLower", priceOfWethInUsdcLower);
        console.log("priceOfUsdcInWethUpper", priceOfUsdcInWethUpper);
        console.log("priceOfWethInUsdcUpper", priceOfWethInUsdcUpper);

        vm.stopPrank();

        console.log("amount0", amount0); // 63890307123541149 = 0.063890307123541149 WETH
        console.log("amount1", amount1); // 1000000000 = 1000.000000 usdc

        // UNISWAP deposit
        vm.startPrank(user);
        IERC20(WETH).approve(address(nonfungiblePositionManager), amountWETH);
        IERC20(USDC).approve(address(nonfungiblePositionManager), amountUSDC);
        (, uint128 liquidityUniswap, uint256 amount0Uniswap, uint256 amount1Uniswap) = INonfungiblePositionManager(
            nonfungiblePositionManager
        ).mint(
            INonfungiblePositionManager.MintParams({
                token0: USDC,
                token1: WETH,
                fee: USDC_WETH_FEE,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: uint128(amountUSDC),
                amount1Desired: uint128(amountWETH),
                amount0Min: 0,
                amount1Min: 0,
                recipient: user,
                deadline: block.timestamp + 1000
            })
        );

        IUniswapV3Adapter.Position[] memory positionsAfterUniswap = adapter.getUserPositions(user);
        assertEq(positionsAfterUniswap.length, 2);

        int24 tickLowerUniswap = positionsAfterUniswap[1].tickLower;
        int24 tickUpperUniswap = positionsAfterUniswap[1].tickUpper;
        uint256 liquidityUniswapFromPosition1 = positionsAfterUniswap[1].liquidity;
        uint256 liquidityUniswapFromPosition0 = positionsAfterUniswap[0].liquidity;
        assertEq(tickLowerUniswap, 197680);
        assertEq(tickUpperUniswap, 198920);

        // adapter and uniswap deposit in different order, but same amount
        // if amounts and liquidity are equal, it means adapter works correctly
        assertEq(amount0Uniswap, amount1);
        assertEq(amount1Uniswap, amount0);
        assertEq(liquidityUniswapFromPosition1, liquidityUniswapFromPosition0);
        assertEq(liquidityUniswap, liquidityUniswapFromPosition1);

        vm.stopPrank();
    }

    function testAddLiquidityInCorrectOrderPrices() public {
        uint256 amountWETH = 1e18;
        uint256 amountUSDC = 1000e6;

        uint256 priceLowerToProvide = 0.000384 * 1e18;
        uint256 priceUpperToProvide = 0.000435 * 1e18;

        // test check by same price ticks and amounts in
        // ADAPTER deposit

        vm.startPrank(user);
        IERC20(WETH).approve(address(adapter), amountWETH);
        IERC20(USDC).approve(address(adapter), amountUSDC);

        (uint256 amount0, uint256 amount1) = adapter.addLiquidity(
            IUniswapV3Adapter.AddLiquidityParams({
                token0: USDC,
                token1: WETH,
                fee: USDC_WETH_FEE,
                priceLower: priceLowerToProvide,
                priceUpper: priceUpperToProvide,
                amount0Desired: uint128(amountUSDC),
                amount1Desired: uint128(amountWETH),
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1000
            })
        );

        IUniswapV3Adapter.Position[] memory positions = adapter.getUserPositions(user);
        assertEq(positions.length, 1);

        int24 tickLower = positions[0].tickLower; //197670
        int24 tickUpper = positions[0].tickUpper; //198920
        assertEq(tickLower, 197670);
        assertEq(tickUpper, 198920);

        uint160 sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(tickUpper);

        uint256 priceOfUsdcInWethLower = FullMath.mulDiv(sqrtPriceX96Lower, sqrtPriceX96Lower, 1 << 192) * 1e6; // 383945708000000 = 0.0003839457 WETH
        uint256 priceOfWethInUsdcLower = (1e18 * 1e18) / priceOfUsdcInWethLower; // 2604534909920128603182 = 2604.534909920128603182 USDC

        uint256 priceOfUsdcInWethUpper = FullMath.mulDiv(sqrtPriceX96Upper, sqrtPriceX96Upper, 1 << 192) * 1e6; // 435064766000000 = 0.000435064766 WETH
        uint256 priceOfWethInUsdcUpper = (1e18 * 1e18) / priceOfUsdcInWethUpper; // 2298508355880053040194 = 2298.508355880053040194 USDC

        assertApproxEqRel(priceLowerToProvide, priceOfUsdcInWethLower, 1e18 * 5 / 100);
        assertApproxEqRel(priceUpperToProvide, priceOfUsdcInWethUpper, 1e18 * 5 / 100);

        console.log("priceOfUsdcInWethLower", priceOfUsdcInWethLower);
        console.log("priceOfWethInUsdcLower", priceOfWethInUsdcLower);
        console.log("priceOfUsdcInWethUpper", priceOfUsdcInWethUpper);
        console.log("priceOfWethInUsdcUpper", priceOfWethInUsdcUpper);

        vm.stopPrank();

        // UNISWAP deposit
        vm.startPrank(user);
        IERC20(WETH).approve(address(nonfungiblePositionManager), amountWETH);
        IERC20(USDC).approve(address(nonfungiblePositionManager), amountUSDC);
        (, uint128 liquidityUniswap, uint256 amount0Uniswap, uint256 amount1Uniswap) = INonfungiblePositionManager(
            nonfungiblePositionManager
        ).mint(
            INonfungiblePositionManager.MintParams({
                token0: USDC,
                token1: WETH,
                fee: USDC_WETH_FEE,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: uint128(amountUSDC),
                amount1Desired: uint128(amountWETH),
                amount0Min: 0,
                amount1Min: 0,
                recipient: user,
                deadline: block.timestamp + 1000
            })
        );

        IUniswapV3Adapter.Position[] memory positionsAfterUniswap = adapter.getUserPositions(user);
        assertEq(positionsAfterUniswap.length, 2);

        int24 tickLowerUniswap = positionsAfterUniswap[1].tickLower;
        int24 tickUpperUniswap = positionsAfterUniswap[1].tickUpper;
        uint256 liquidityUniswapFromPosition1 = positionsAfterUniswap[1].liquidity;
        uint256 liquidityUniswapFromPosition0 = positionsAfterUniswap[0].liquidity;
        assertEq(tickLowerUniswap, 197670);
        assertEq(tickUpperUniswap, 198920);

        // adapter and uniswap deposit in correct order, and same amount
        // if amounts and liquidity are equal, it means adapter works correctly
        assertEq(amount0Uniswap, amount0);
        assertEq(amount1Uniswap, amount1);
        assertEq(liquidityUniswapFromPosition1, liquidityUniswapFromPosition0);
        assertEq(liquidityUniswap, liquidityUniswapFromPosition1);

        vm.stopPrank();
    }
}
