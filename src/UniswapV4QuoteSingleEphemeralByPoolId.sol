// SPDX-License-Identifier: LicenseRef-CICADA-Proprietary
// SPDX-FileCopyrightText: (c) 2024 Cicada Software, CICADA DMCC. All rights reserved.
pragma solidity ^0.8.24;

import {UniswapV4QuoteSingle} from "./UniswapV4QuoteSingle.sol";

/**
 * @notice Ephemeral factory for quoting by poolId. Deploys quoter and calls quoteByPoolId();
 *         Fetches poolManager and PoolKey from PositionManager on-chain. Reverts with AmountOut.
 * @dev Same pattern as UniswapV4QuoteSingleEphemeral but uses poolId lookup instead of explicit PoolKey.
 */
contract UniswapV4QuoteSingleEphemeralByPoolId {
    constructor(
        address positionManager,
        bytes32 poolId,
        address tokenIn,
        uint256 amountIn,
        uint256 protocolFeeBps
    ) {
        UniswapV4QuoteSingle q = new UniswapV4QuoteSingle();
        q.quoteByPoolId(positionManager, poolId, tokenIn, amountIn, protocolFeeBps);
    }
}
