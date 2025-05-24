// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {UniswapV3Adapter} from "../src/UniswapV3Adapter.sol";
import {IUniswapV3Adapter} from "../src/interfaces/IUniswapV3Adapter.sol";

/**
 * Tests are run on EVM L1
 */
contract UniswapV3AdapterTest is Test {
    // Mainnet information
    uint256 public BLOCK_NUMBER = 22554182;
    IUniswapV3Factory public factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IQuoterV2 public quoter = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint24 public USDC_WETH_FEE = 500;
    address public USDC_WETH_500_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    IUniswapV3Adapter public adapter;

    function setUp() public {
        vm.createSelectFork("evm", BLOCK_NUMBER);
        adapter = new UniswapV3Adapter(
            address(factory), address(nonfungiblePositionManager), address(swapRouter), address(quoter)
        );
    }

    function test_getPoolAddress() public {
        address pool = adapter.getPoolAddress(USDC, WETH, USDC_WETH_FEE);
        assertEq(pool, USDC_WETH_500_POOL);
    }

    function test_getExpectedAmountOut() public {
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
}
