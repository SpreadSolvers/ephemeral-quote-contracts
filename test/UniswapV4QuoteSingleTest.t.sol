// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Fork tests for UniswapV4QuoteSingle. Compares against official V4 Quoter.
/// @dev Set ETHEREUM_RPC_URL or RPC_URL to run. Fork block 21_700_000 for caching.

import {Test} from "forge-std/Test.sol";
import {UniswapV4QuoteSingle} from "../src/UniswapV4QuoteSingle.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

interface IV4Quoter {
    struct QuoteExactSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 exactAmount;
        bytes hookData;
    }

    function quoteExactInputSingle(QuoteExactSingleParams memory params)
        external
        returns (uint256 amountOut, uint256 gasEstimate);
}

/**
 * @title V4QuoteSingleHelper
 * @dev Catches AmountOut revert and returns decoded amountOut.
 *      Re-reverts InsufficientLiquidity so callers can detect it.
 */
contract V4QuoteSingleHelper {
    UniswapV4QuoteSingle public quoter;

    constructor() {
        quoter = new UniswapV4QuoteSingle();
    }

    function getAmountOut(
        address poolManager,
        PoolKey calldata key,
        address tokenIn,
        uint256 amountIn,
        uint256 protocolFeeBps
    ) external returns (uint256 amountOut) {
        try quoter.quote(poolManager, key, tokenIn, amountIn, protocolFeeBps) {
            revert("V4QuoteSingleHelper: expected revert");
        } catch (bytes memory reason) {
            require(reason.length >= 4, "V4QuoteSingleHelper: no revert data");

            bytes4 selector;
            // forge-lint: disable-next-line(unsafe-typecast)
            selector = bytes4(reason);

            if (
                selector == UniswapV4QuoteSingle.InsufficientLiquidity.selector
                    || selector == IPoolManager.PoolNotInitialized.selector
            ) {
                assembly {
                    revert(add(reason, 0x20), mload(reason))
                }
            }

            require(reason.length >= 36, "V4QuoteSingleHelper: unexpected revert data");
            bytes memory payload = new bytes(reason.length - 4);
            for (uint256 j; j < payload.length; j++) {
                payload[j] = reason[j + 4];
            }
            amountOut = abi.decode(payload, (uint256));
        }
    }
}

contract UniswapV4QuoteSingleTest is Test {
    V4QuoteSingleHelper public helper;

    // Uniswap V4 on Ethereum mainnet
    address constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant QUOTER = 0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203;

    // USDC/WETH 0.05% pool — USDC (0xA0..) < WETH (0xC0..) so currency0=USDC, currency1=WETH
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint24 constant FEE = 500;
    int24 constant TICK_SPACING = 10;

    uint256 constant ETH_FORK_BLOCK = 21_700_000;

    function _poolKey() internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(WETH),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });
    }

    function setUp() public {
        string memory rpcUrl = vm.envOr("ETHEREUM_RPC_URL", vm.envOr("RPC_URL", string("")));
        vm.skip(bytes(rpcUrl).length == 0);
        vm.createSelectFork(rpcUrl, ETH_FORK_BLOCK);
        helper = new V4QuoteSingleHelper();
    }

    function testFork_QuoteMatchesOfficialQuoter_UsdcToWeth() public {
        uint256 amountIn = 1_000_000; // 1 USDC (6 decimals)

        uint256 ourQuote = helper.getAmountOut(POOL_MANAGER, _poolKey(), USDC, amountIn, 0);

        (uint256 officialAmountOut,) = IV4Quoter(QUOTER)
            .quoteExactInputSingle(
                IV4Quoter.QuoteExactSingleParams({
                    poolKey: _poolKey(), zeroForOne: true, exactAmount: uint128(amountIn), hookData: ""
                })
            );

        assertEq(ourQuote, officialAmountOut, "UniswapV4QuoteSingle != official V4 Quoter");
    }

    function testFork_QuoteMatchesOfficialQuoter_WethToUsdc() public {
        uint256 amountIn = 1e18; // 1 WETH

        uint256 ourQuote = helper.getAmountOut(POOL_MANAGER, _poolKey(), WETH, amountIn, 0);

        (uint256 officialAmountOut,) = IV4Quoter(QUOTER)
            .quoteExactInputSingle(
                IV4Quoter.QuoteExactSingleParams({
                    poolKey: _poolKey(), zeroForOne: false, exactAmount: uint128(amountIn), hookData: ""
                })
            );

        assertEq(ourQuote, officialAmountOut, "UniswapV4QuoteSingle != official V4 Quoter");
    }

    function testFork_ProtocolFeeReducesAmountOut() public {
        uint256 amountIn = 1_000_000; // 1 USDC
        uint256 protocolFeeBps = 300; // 3%

        uint256 quoteNoFee = helper.getAmountOut(POOL_MANAGER, _poolKey(), USDC, amountIn, 0);
        uint256 quoteWithFee = helper.getAmountOut(POOL_MANAGER, _poolKey(), USDC, amountIn, protocolFeeBps);

        uint256 expectedWithFee = (quoteNoFee * (10_000 - protocolFeeBps)) / 10_000;
        assertEq(quoteWithFee, expectedWithFee, "protocol fee not applied correctly");
    }

    function testFork_quote_RevertOn_PoolNotInitialized() public {
        PoolKey memory uninitKey = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(WETH),
            fee: 9999, // pool with this fee tier has never been initialized
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        UniswapV4QuoteSingle quoter = new UniswapV4QuoteSingle();
        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        quoter.quote(POOL_MANAGER, uninitKey, USDC, 1_000_000, 0);
    }
}
