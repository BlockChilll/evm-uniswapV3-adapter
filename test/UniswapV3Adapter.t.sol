// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {UniswapV3Adapter} from "../src/UniswapV3Adapter.sol";
import {IUniswapV3Adapter} from "../src/interfaces/IUniswapV3Adapter.sol";

/**
 * Tests are run on EVM L1
 */
contract UniswapV3AdapterTest is Test {
    // Mainnet information
    uint256 public BLOCK_NUMBER = 22554182;
    IUniswapV3Factory public factory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    ISwapRouter public swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IQuoterV2 public quoter =
        IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public USDC_WETH_500_POOL =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    IUniswapV3Adapter public adapter;

    function setUp() public {
        vm.createSelectFork("evm", BLOCK_NUMBER);
        adapter = new UniswapV3Adapter(
            address(factory),
            address(nonfungiblePositionManager),
            address(swapRouter)
        );
    }

    function test_getPoolAddress() public {
        address pool = adapter.getPoolAddress(USDC, WETH, 500);
        assertEq(pool, USDC_WETH_500_POOL);
    }
}
