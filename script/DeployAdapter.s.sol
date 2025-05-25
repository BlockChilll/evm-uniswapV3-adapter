// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

import {UniswapV3Adapter} from "../src/UniswapV3Adapter.sol";

contract DeployAdapter is Script {
    function run(address _factory, address _nonfungiblePositionManager, address _swapRouter, address _quoter)
        external
        returns (UniswapV3Adapter adapter)
    {
        vm.startBroadcast();
        adapter = new UniswapV3Adapter(_factory, _nonfungiblePositionManager, _swapRouter, _quoter);
        vm.stopBroadcast();
    }
}
