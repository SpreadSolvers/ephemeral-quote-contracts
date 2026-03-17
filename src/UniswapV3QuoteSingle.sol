// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {SafeCast} from "v3-core/contracts/libraries/SafeCast.sol";

/**
 * @notice Quotes output for Uniswap V3 pool (exact input single).
 * @dev Uses pool.swap() and reverts in callback with amountOut. Must be deployed and called via
 *      quote(); ephemeral `new` fails because the pool callback targets an address with no code yet.
 *      Set protocolFeeBps to match frontend "amount received" when router takes a cut. Use 0 for raw quote.
 */
contract UniswapV3QuoteSingle is IUniswapV3SwapCallback {
    error AmountOut(uint256 amountOut);

    uint160 private constant MIN_SQRT_RATIO_PLUS_ONE = 4295128740;
    uint160 private constant MAX_SQRT_RATIO_MINUS_ONE = 1461446703485210103287273052203988822378723970341;

    /**
     * @param pool           V3 pool address.
     * @param tokenIn        Input token (token0 or token1).
     * @param amountIn       Input amount.
     * @param protocolFeeBps Optional fee in basis points deducted from amountOut. Use 0 for raw quote.
     */
    function quote(address pool, address tokenIn, uint256 amountIn, uint256 protocolFeeBps) external {
        IUniswapV3Pool v3Pool = IUniswapV3Pool(pool);
        address token0 = v3Pool.token0();
        bool zeroForOne = tokenIn == token0;

        uint160 sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO_PLUS_ONE : MAX_SQRT_RATIO_MINUS_ONE;

        v3Pool.swap(
            address(this), zeroForOne, SafeCast.toInt256(amountIn), sqrtPriceLimitX96, abi.encode(protocolFeeBps)
        );
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
        external
        pure
        override
    {
        uint256 amountOut = amount0Delta > 0 ? uint256(-amount1Delta) : uint256(-amount0Delta);
        uint256 protocolFeeBps = abi.decode(data, (uint256));
        if (protocolFeeBps > 0 && protocolFeeBps < 10_000) {
            amountOut = (amountOut * (10_000 - protocolFeeBps)) / 10_000;
        }
        revert AmountOut(amountOut);
    }
}
