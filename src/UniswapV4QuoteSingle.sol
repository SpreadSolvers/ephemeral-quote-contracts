// SPDX-License-Identifier: LicenseRef-CICADA-Proprietary
// SPDX-FileCopyrightText: (c) 2024 Cicada Software, CICADA DMCC. All rights reserved.
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";

/**
 * @notice Quotes output for Uniswap V4 pool (exact input single).
 * @dev Uses PoolManager.unlock() → unlockCallback() → swap() and reverts in callback with amountOut.
 *      Must be deployed before calling quote() because unlock() requires the callback caller has code.
 *      Set protocolFeeBps to match frontend "amount received" when router takes a cut. Use 0 for raw quote.
 */
contract UniswapV4QuoteSingle is IUnlockCallback {
    /* ======== ERRORS ======== */

    error AmountOut(uint256 amountOut);
    error InsufficientLiquidity();

    /* ======== STATE ======== */

    uint160 private constant MIN_SQRT_RATIO_PLUS_ONE = 4295128740;
    uint160 private constant MAX_SQRT_RATIO_MINUS_ONE = 1461446703485210103287273052203988822378723970341;

    /* ======== EXTERNAL/PUBLIC ======== */

    /**
     * @param poolManager    V4 PoolManager singleton address.
     * @param key            Pool key identifying the V4 pool.
     * @param tokenIn        Input token (currency0 or currency1).
     * @param amountIn       Input amount.
     * @param protocolFeeBps Optional fee in basis points deducted from amountOut. Use 0 for raw quote.
     */
    function quote(address poolManager, PoolKey calldata key, address tokenIn, uint256 amountIn, uint256 protocolFeeBps)
        external
    {
        IPoolManager(poolManager).unlock(abi.encode(poolManager, key, tokenIn, amountIn, protocolFeeBps));
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        (address poolManager, PoolKey memory key, address tokenIn, uint256 amountIn, uint256 protocolFeeBps) =
            abi.decode(data, (address, PoolKey, address, uint256, uint256));

        bool zeroForOne = tokenIn == Currency.unwrap(key.currency0);

        BalanceDelta delta = IPoolManager(poolManager)
            .swap(
                key,
                IPoolManager.SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: -int256(amountIn),
                    sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_RATIO_PLUS_ONE : MAX_SQRT_RATIO_MINUS_ONE
                }),
                ""
            );

        uint256 amountOut = zeroForOne ? uint256(uint128(-delta.amount1())) : uint256(uint128(-delta.amount0()));

        if (amountOut == 0) revert InsufficientLiquidity();

        if (protocolFeeBps > 0 && protocolFeeBps < 10_000) {
            amountOut = (amountOut * (10_000 - protocolFeeBps)) / 10_000;
        }

        revert AmountOut(amountOut);
    }
}
