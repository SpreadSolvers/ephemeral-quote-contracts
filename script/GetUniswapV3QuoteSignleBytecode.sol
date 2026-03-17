// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {UniswapV3QuoteSingleEphemeral} from "src/UniswapV3QuoteSingleEphemeral.sol";

contract GetUniswapV3QuoteSingleEphemeralBytecode is Script {
    function run() public pure returns (bytes memory) {
        bytes memory bytecode = type(UniswapV3QuoteSingleEphemeral).creationCode;
        return bytecode;
    }
}
