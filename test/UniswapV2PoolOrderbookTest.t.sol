// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Fork tests for UniswapV2PoolOrderbook. Set ETHEREUM_RPC_URL or RPC_URL to run.
/// @dev Tests skip when RPC not set. Fork block 21_500_000 for caching.

import {Test} from "forge-std/Test.sol";
import {UniswapV2PoolOrderbook} from "../src/UniswapV2PoolOrderbook.sol";
import {IUniswapV2Pair} from "../src/interfaces/IUniswapV2Pair.sol";

/**
 * @title OrderbookHelper
 * @dev Catches OrderbookAmounts revert and returns decoded data for assertions.
 */
contract OrderbookHelper {
    struct Amounts {
        uint256[] amountsIn;
        uint256[] amountsOut;
    }

    function getOrderbook(
        address pool,
        address quoteToken,
        uint256 amountStart,
        uint256 amountIncrementBps,
        uint256 steps,
        uint256 protocolFeeBps
    ) external returns (Amounts memory exactIn, Amounts memory exactOut) {
        try new UniswapV2PoolOrderbook(pool, quoteToken, amountStart, amountIncrementBps, steps, protocolFeeBps) {
            revert("OrderbookHelper: expected revert");
        } catch (bytes memory reason) {
            require(reason.length > 4, "OrderbookHelper: no revert data");
            bytes memory payload = new bytes(reason.length - 4);
            for (uint256 j; j < payload.length; j++) {
                payload[j] = reason[j + 4];
            }
            (Amounts memory exactInDecoded, Amounts memory exactOutDecoded) = abi.decode(payload, (Amounts, Amounts));
            return (exactInDecoded, exactOutDecoded);
        }
    }
}

contract UniswapV2PoolOrderbookTest is Test {
    OrderbookHelper public helper;

    // Uniswap V2 WBTC/WETH pool on Ethereum mainnet
    address constant POOL = 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 constant ETH_FORK_BLOCK = 21_500_000;

    function setUp() public {
        string memory rpcUrl = vm.envOr("ETHEREUM_RPC_URL", vm.envOr("RPC_URL", string("")));
        vm.skip(bytes(rpcUrl).length == 0);
        vm.createSelectFork(rpcUrl, ETH_FORK_BLOCK);
        helper = new OrderbookHelper();
    }

    function testFork_RevertsWithOrderbookAmounts() public {
        vm.expectRevert();
        new UniswapV2PoolOrderbook(
            POOL,
            WETH,
            1e16, // 0.01 WETH
            100, // 1% per step
            3,
            0
        );
    }

    function testFork_AmountsInFollowFormula() public {
        uint256 amountStart = 1e16;
        uint256 amountIncrementBps = 100;
        uint256 steps = 5;

        (OrderbookHelper.Amounts memory exactIn,) =
            helper.getOrderbook(POOL, WETH, amountStart, amountIncrementBps, steps, 0);

        assertEq(exactIn.amountsIn.length, steps, "steps");
        for (uint256 i; i < steps; i++) {
            uint256 expected = (amountStart * (10_000 + amountIncrementBps * i)) / 10_000;
            assertEq(exactIn.amountsIn[i], expected, "amountsIn formula");
        }
    }

    function testFork_ExactInAmountsOutMatchesGetAmountOut() public {
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(POOL).getReserves();
        address token0 = IUniswapV2Pair(POOL).token0();
        (uint256 reserveIn, uint256 reserveOut) = WETH == token0 ? (reserve0, reserve1) : (reserve1, reserve0);

        uint256 amountStart = 1e16;
        uint256 amountIncrementBps = 50;
        uint256 steps = 3;

        (OrderbookHelper.Amounts memory exactIn,) =
            helper.getOrderbook(POOL, WETH, amountStart, amountIncrementBps, steps, 0);

        for (uint256 i; i < steps; i++) {
            uint256 expectedOut = _getAmountOut(exactIn.amountsIn[i], reserveIn, reserveOut);
            assertEq(exactIn.amountsOut[i], expectedOut, "exactIn amountsOut");
        }
    }

    function testFork_ProtocolFeeReducesAmountOut() public {
        uint256 amountStart = 1e16;
        uint256 steps = 2;
        uint256 protocolFeeBps = 300; // 3%

        (OrderbookHelper.Amounts memory exactInNoFee,) = helper.getOrderbook(POOL, WETH, amountStart, 0, steps, 0);
        (OrderbookHelper.Amounts memory exactInWithFee,) =
            helper.getOrderbook(POOL, WETH, amountStart, 0, steps, protocolFeeBps);

        for (uint256 i; i < steps; i++) {
            uint256 expectedWithFee = (exactInNoFee.amountsOut[i] * (10_000 - protocolFeeBps)) / 10_000;
            assertEq(exactInWithFee.amountsOut[i], expectedWithFee, "protocol fee applied");
        }
    }

    function testFork_ExactOutAmountInGreaterOrEqualExactIn() public {
        uint256 amountStart = 1e16;
        uint256 steps = 4;

        (OrderbookHelper.Amounts memory exactIn, OrderbookHelper.Amounts memory exactOut) =
            helper.getOrderbook(POOL, WETH, amountStart, 100, steps, 0);

        for (uint256 i; i < steps; i++) {
            // Allow rounding tolerance (Uniswap V2 getAmountIn/getAmountOut inverse can differ slightly)
            assertGe(
                exactOut.amountsIn[i],
                exactIn.amountsIn[i] - (exactIn.amountsIn[i] / 10_000),
                "exactOut amountIn >= exactIn amountIn (with rounding tolerance)"
            );
        }
    }

    function testFork_SingleStep() public {
        uint256 amountStart = 5e15; // 0.005 WETH

        (OrderbookHelper.Amounts memory exactIn, OrderbookHelper.Amounts memory exactOut) =
            helper.getOrderbook(POOL, WETH, amountStart, 0, 1, 0);

        assertEq(exactIn.amountsIn.length, 1);
        assertEq(exactIn.amountsIn[0], amountStart);
        assertGt(exactIn.amountsOut[0], 0);
        assertEq(exactOut.amountsOut[0], exactIn.amountsOut[0]);
        // Allow rounding tolerance (getAmountIn can round down slightly vs exact-in)
        assertGe(exactOut.amountsIn[0], amountStart - (amountStart / 10_000), "exactOut amountIn >= amountStart");
    }

    function testFork_QuoteTokenAsToken1() public {
        address token0 = IUniswapV2Pair(POOL).token0();

        address quoteToken = token0 == WETH ? WBTC : WETH;
        uint256 amountStart = quoteToken == WBTC ? 1e8 : 1e16; // 1 WBTC or 0.01 WETH

        (OrderbookHelper.Amounts memory exactIn,) = helper.getOrderbook(POOL, quoteToken, amountStart, 0, 2, 0);

        assertEq(exactIn.amountsIn.length, 2);
        assertGt(exactIn.amountsOut[0], 0);
        assertGt(exactIn.amountsOut[1], 0);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        return numerator / denominator;
    }
}
