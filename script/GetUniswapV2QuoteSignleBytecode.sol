// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {UniswapV2QuoteSingle} from "../src/UniswapV2QuoteSingle.sol";

contract GetUniswapV2QuoteSingleBytecode is Script {
    function run() public pure returns (bytes memory) {
        bytes memory bytecode = type(UniswapV2QuoteSingle).creationCode;
        return bytecode;
    }
}
