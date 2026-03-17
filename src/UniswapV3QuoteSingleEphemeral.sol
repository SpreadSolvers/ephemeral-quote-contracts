// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UniswapV3QuoteSingle} from "./UniswapV3QuoteSingle.sol";

/**
 * @notice Ephemeral factory for UniswapV3QuoteSingle. Deploys quoter and calls quote();
 *        reverts with AmountOut. Used by off-chain quoters (e.g. Rust) via CREATE + constructor args.
 * @dev UniswapV3QuoteSingle cannot be used ephemerally (new X(...)) because the pool callback
 *      targets an address with no code during CREATE. This factory deploys it first, then calls.
 */
contract UniswapV3QuoteSingleEphemeral {
    constructor(address pool, address tokenIn, uint256 amountIn, uint256 protocolFeeBps) {
        UniswapV3QuoteSingle q = new UniswapV3QuoteSingle();
        q.quote(pool, tokenIn, amountIn, protocolFeeBps);
    }
}
