// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {UniswapV3QuoteSingle} from "../src/UniswapV3QuoteSingle.sol";

contract GetUniswapV3QuoteSingleBytecode is Script {
    function run() public pure returns (bytes memory) {
        bytes memory bytecode = type(UniswapV3QuoteSingle).creationCode;
        return bytecode;
    }
}
