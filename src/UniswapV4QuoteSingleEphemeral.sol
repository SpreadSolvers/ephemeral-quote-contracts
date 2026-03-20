// SPDX-License-Identifier: LicenseRef-CICADA-Proprietary
// SPDX-FileCopyrightText: (c) 2024 Cicada Software, CICADA DMCC. All rights reserved.
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {UniswapV4QuoteSingle} from "./UniswapV4QuoteSingle.sol";

/**
 * @notice Ephemeral factory for UniswapV4QuoteSingle. Deploys quoter and calls quote();
 *         reverts with AmountOut. Used by off-chain quoters (e.g. Rust) via CREATE + constructor args.
 * @dev UniswapV4QuoteSingle cannot be used ephemerally (new X(...)) because PoolManager.unlock()
 *      requires the callback caller to have code deployed at its address before the call.
 *      This factory deploys it first, then calls quote().
 */
contract UniswapV4QuoteSingleEphemeral {
    constructor(address poolManager, PoolKey memory key, address tokenIn, uint256 amountIn, uint256 protocolFeeBps) {
        UniswapV4QuoteSingle q = new UniswapV4QuoteSingle();
        q.quote(poolManager, key, tokenIn, amountIn, protocolFeeBps);
    }
}
