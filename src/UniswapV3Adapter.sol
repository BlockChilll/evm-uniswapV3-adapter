// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {PoolAddress} from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
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
    /**
     * @dev code hash used in deployed uniswap PoolAddress lib to calculate deterministic pool address
     * PoolAddress lib from 0.8 compatible version used for our code has different hash, so cannot be used for pool address calculations
     */
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    IUniswapV3Factory public immutable i_factory;
    ISwapRouter public immutable i_swapRouter;
    INonfungiblePositionManager public immutable i_nonfungiblePositionManager;

    constructor(
        address _factory,
        address _nonfungiblePositionManager,
        address _swapRouter
    ) {
        i_factory = IUniswapV3Factory(_factory);
        i_nonfungiblePositionManager = INonfungiblePositionManager(
            _nonfungiblePositionManager
        );
        i_swapRouter = ISwapRouter(_swapRouter);
    }

    function getPoolAddress(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool) {
        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(
            tokenA,
            tokenB,
            fee
        );
        pool = computeAddress(address(i_factory), poolKey);
    }

    /**
     * @dev This function is used to compute the pool address given the factory and PoolKey
     * @param factory The Uniswap V3 factory contract address
     * @param key The PoolKey
     * @return pool The contract address of the V3 pool
     * @notice This is copied from the Uniswap V3 PoolAddress library. Need it to use correct hash for pool address calculation
     * 0.8 compatible version of PoolAddress library has different hash, so cannot be used for pool address calculations
     * we use 0.8 compatible version of PoolAddress library for our code to be compatible with our codebase
     */
    function computeAddress(
        address factory,
        PoolAddress.PoolKey memory key
    ) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(
                                abi.encode(key.token0, key.token1, key.fee)
                            ),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}
