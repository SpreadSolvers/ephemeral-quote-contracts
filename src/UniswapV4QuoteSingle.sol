// SPDX-License-Identifier: LicenseRef-CICADA-Proprietary
// SPDX-FileCopyrightText: (c) 2024 Cicada Software, CICADA DMCC. All rights reserved.
pragma solidity ^0.8.24;

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

/**
 * @notice Quotes output for Uniswap V4 pool (exact input single).
 * @dev Uses PoolManager.unlock() → unlockCallback() → swap() and reverts in callback with amountOut.
 *      Must be deployed before calling quote() because unlock() requires the callback caller has code.
 *      Set protocolFeeBps to match frontend "amount received" when router takes a cut. Use 0 for raw quote.
 *
 * @dev BalanceDelta sign convention (from the caller's perspective):
 *      positive amount  → you RECEIVE that token (pool owes you)
 *      negative amount  → you PAY that token (you owe the pool)
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

    /**
     * @notice Quote by poolId. Fetches poolManager and PoolKey from PositionManager on-chain.
     * @param positionManager PositionManager contract address (e.g. 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e on Ethereum).
     * @param poolId         bytes32 pool identifier (keccak256(abi.encode(poolKey))); stripped to bytes25 for PositionManager lookup.
     * @param tokenIn        Input token (currency0 or currency1).
     * @param amountIn       Input amount.
     * @param protocolFeeBps Optional fee in basis points deducted from amountOut. Use 0 for raw quote.
     */
    function quoteByPoolId(
        address positionManager,
        bytes32 poolId,
        address tokenIn,
        uint256 amountIn,
        uint256 protocolFeeBps
    ) external {
        bytes25 poolId25 = bytes25(uint200(uint256(poolId) >> 56));
        address poolManager = IPositionManager(positionManager).poolManager();
        (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) =
            IPositionManager(positionManager).poolKeys(poolId25);
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks});
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
                SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: -int256(amountIn),
                    sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_RATIO_PLUS_ONE : MAX_SQRT_RATIO_MINUS_ONE
                }),
                ""
            );

        // BalanceDelta: positive = you RECEIVE, negative = you PAY.
        // For zeroForOne: amount1 > 0 is the token1 (tokenOut) you receive.
        // For !zeroForOne: amount0 > 0 is the token0 (tokenOut) you receive.
        uint256 amountOut = zeroForOne ? uint256(uint128(delta.amount1())) : uint256(uint128(delta.amount0()));

        if (amountOut == 0) revert InsufficientLiquidity();

        if (protocolFeeBps > 0 && protocolFeeBps < 10_000) {
            amountOut = (amountOut * (10_000 - protocolFeeBps)) / 10_000;
        }

        revert AmountOut(amountOut);
    }
}
