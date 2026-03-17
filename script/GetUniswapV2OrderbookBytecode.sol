// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {UniswapV2PoolOrderbook} from "../src/UniswapV2PoolOrderbook.sol";

contract GetUniswapV2OrderbookBytecode is Script {
    function run() public pure returns (bytes memory) {
        bytes memory bytecode = type(UniswapV2PoolOrderbook).creationCode;
        return bytecode;
    }
}
