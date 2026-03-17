// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Fork tests for UniswapV2PoolOrderbook. Set FUSE_RPC_URL or RPC_URL to run.
/// @dev Tests skip (pass no-op) when RPC not set. Fork block 40967484 for caching.

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
        try new UniswapV2PoolOrderbook(
            pool, quoteToken, amountStart, amountIncrementBps, steps, protocolFeeBps
        ) {
            revert("OrderbookHelper: expected revert");
        } catch (bytes memory reason) {
            require(reason.length > 4, "OrderbookHelper: no revert data");
            bytes memory payload = new bytes(reason.length - 4);
            for (uint256 j; j < payload.length; j++) {
                payload[j] = reason[j + 4];
            }
            (Amounts memory exactInDecoded, Amounts memory exactOutDecoded) =
                abi.decode(payload, (Amounts, Amounts));
            return (exactInDecoded, exactOutDecoded);
        }
    }
}

contract UniswapV2PoolOrderbookTest is Test {
    OrderbookHelper public helper;

    // Fuse Voltage WBTC/WETH pool
    address constant POOL = 0x97F4F45F0172F2E20Ab284A61C8adcf5E4d04228;
    address constant WBTC = 0x33284f95ccb7B948d9D352e1439561CF83d8d00d;
    address constant WETH = 0xa722c13135930332Eb3d749B2F0906559D2C5b99;

    uint256 constant FUSE_FORK_BLOCK = 40_967_484;

    function setUp() public {
        string memory rpcUrl = vm.envOr("FUSE_RPC_URL", vm.envOr("RPC_URL", string("")));
        if (bytes(rpcUrl).length == 0) {
            return;
        }
        vm.createSelectFork(rpcUrl, FUSE_FORK_BLOCK);
        helper = new OrderbookHelper();
    }

    function testFork_RevertsWithOrderbookAmounts() public {
        if (address(helper) == address(0)) return;

        vm.expectRevert();
        new UniswapV2PoolOrderbook(
            POOL,
            WETH,
            1e16, // 0.01 WETH
            100,  // 1% per step
            3,
            0
        );
    }

    function testFork_AmountsInFollowFormula() public {
        if (address(helper) == address(0)) return;

        uint256 amountStart = 1e16;
        uint256 amountIncrementBps = 100;
        uint256 steps = 5;

        (OrderbookHelper.Amounts memory exactIn,) = helper.getOrderbook(
            POOL, WETH, amountStart, amountIncrementBps, steps, 0
        );

        assertEq(exactIn.amountsIn.length, steps, "steps");
        for (uint256 i; i < steps; i++) {
            uint256 expected = (amountStart * (10_000 + amountIncrementBps * i)) / 10_000;
            assertEq(exactIn.amountsIn[i], expected, "amountsIn formula");
        }
    }

    function testFork_ExactInAmountsOutMatchesGetAmountOut() public {
        if (address(helper) == address(0)) return;

        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(POOL).getReserves();
        address token0 = IUniswapV2Pair(POOL).token0();
        (uint256 reserveIn, uint256 reserveOut) = WETH == token0 ? (reserve0, reserve1) : (reserve1, reserve0);

        uint256 amountStart = 1e16;
        uint256 amountIncrementBps = 50;
        uint256 steps = 3;

        (OrderbookHelper.Amounts memory exactIn,) = helper.getOrderbook(
            POOL, WETH, amountStart, amountIncrementBps, steps, 0
        );

        for (uint256 i; i < steps; i++) {
            uint256 expectedOut = _getAmountOut(exactIn.amountsIn[i], reserveIn, reserveOut);
            assertEq(exactIn.amountsOut[i], expectedOut, "exactIn amountsOut");
        }
    }

    function testFork_ProtocolFeeReducesAmountOut() public {
        if (address(helper) == address(0)) return;

        uint256 amountStart = 1e16;
        uint256 steps = 2;
        uint256 protocolFeeBps = 300; // 3%

        (OrderbookHelper.Amounts memory exactInNoFee,) =
            helper.getOrderbook(POOL, WETH, amountStart, 0, steps, 0);
        (OrderbookHelper.Amounts memory exactInWithFee,) =
            helper.getOrderbook(POOL, WETH, amountStart, 0, steps, protocolFeeBps);

        for (uint256 i; i < steps; i++) {
            uint256 expectedWithFee = (exactInNoFee.amountsOut[i] * (10_000 - protocolFeeBps)) / 10_000;
            assertEq(exactInWithFee.amountsOut[i], expectedWithFee, "protocol fee applied");
        }
    }

    function testFork_ExactOutAmountInGreaterOrEqualExactIn() public {
        if (address(helper) == address(0)) return;

        uint256 amountStart = 1e16;
        uint256 steps = 4;

        (OrderbookHelper.Amounts memory exactIn, OrderbookHelper.Amounts memory exactOut) =
            helper.getOrderbook(POOL, WETH, amountStart, 100, steps, 0);

        for (uint256 i; i < steps; i++) {
            assertGe(exactOut.amountsIn[i], exactIn.amountsIn[i], "exactOut amountIn >= exactIn amountIn");
        }
    }

    function testFork_SingleStep() public {
        if (address(helper) == address(0)) return;

        uint256 amountStart = 5e15; // 0.005 WETH

        (OrderbookHelper.Amounts memory exactIn, OrderbookHelper.Amounts memory exactOut) =
            helper.getOrderbook(POOL, WETH, amountStart, 0, 1, 0);

        assertEq(exactIn.amountsIn.length, 1);
        assertEq(exactIn.amountsIn[0], amountStart);
        assertGt(exactIn.amountsOut[0], 0);
        assertEq(exactOut.amountsOut[0], exactIn.amountsOut[0]);
        assertGe(exactOut.amountsIn[0], amountStart);
    }

    function testFork_QuoteTokenAsToken1() public {
        if (address(helper) == address(0)) return;

        address token0 = IUniswapV2Pair(POOL).token0();

        address quoteToken = token0 == WETH ? WBTC : WETH;
        uint256 amountStart = quoteToken == WBTC ? 1e8 : 1e16; // 1 WBTC or 0.01 WETH

        (OrderbookHelper.Amounts memory exactIn,) =
            helper.getOrderbook(POOL, quoteToken, amountStart, 0, 2, 0);

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
