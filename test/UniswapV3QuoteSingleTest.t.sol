// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Fork tests for UniswapV3QuoteSingle. Compares against production QuoterV2.
/// @dev Set ETHEREUM_RPC_URL or RPC_URL to run. Fork block 21500000 for caching.

import {Test} from "forge-std/Test.sol";
import {UniswapV3QuoteSingle} from "../src/UniswapV3QuoteSingle.sol";

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

/**
 * @title QuoteSingleHelper
 * @dev Catches AmountOut revert and returns decoded amountOut.
 */
contract QuoteSingleHelper {
    UniswapV3QuoteSingle public quoter;

    constructor() {
        quoter = new UniswapV3QuoteSingle();
    }

    function getAmountOut(address pool, address tokenIn, uint256 amountIn, uint256 protocolFeeBps)
        external
        returns (uint256 amountOut)
    {
        try quoter.quote(pool, tokenIn, amountIn, protocolFeeBps) {
            revert("QuoteSingleHelper: expected revert");
        } catch (bytes memory reason) {
            require(reason.length >= 36, "QuoteSingleHelper: no revert data");
            bytes memory payload = new bytes(reason.length - 4);
            for (uint256 j; j < payload.length; j++) {
                payload[j] = reason[j + 4];
            }
            amountOut = abi.decode(payload, (uint256));
        }
    }
}

contract UniswapV3QuoteSingleTest is Test {
    QuoteSingleHelper public helper;

    // Uniswap V3 USDC/WETH 0.3% pool on Ethereum (same as QuoterV2 uses)
    address constant POOL = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint24 constant FEE = 3000; // 0.3%

    // QuoterV2 on Ethereum mainnet
    address constant QUOTER_V2 = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;

    uint256 constant ETH_FORK_BLOCK = 21_500_000;

    function setUp() public {
        string memory rpcUrl = vm.envOr("ETHEREUM_RPC_URL", vm.envOr("RPC_URL", string("")));
        vm.skip(bytes(rpcUrl).length == 0);
        vm.createSelectFork(rpcUrl, ETH_FORK_BLOCK);
        helper = new QuoteSingleHelper();
    }

    function testFork_QuoteMatchesQuoterV2_UsdcToWeth() public {
        uint256 amountIn = 1_000_000; // 1 USDC (6 decimals)

        uint256 ourQuote = helper.getAmountOut(POOL, USDC, amountIn, 0);

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: USDC, tokenOut: WETH, amountIn: amountIn, fee: FEE, sqrtPriceLimitX96: 0
        });
        (uint256 quoterV2AmountOut,,,) = IQuoterV2(QUOTER_V2).quoteExactInputSingle(params);

        assertEq(ourQuote, quoterV2AmountOut, "UniswapV3QuoteSingle != QuoterV2");
    }

    function testFork_QuoteMatchesQuoterV2_WethToUsdc() public {
        uint256 amountIn = 1e18; // 1 WETH

        uint256 ourQuote = helper.getAmountOut(POOL, WETH, amountIn, 0);

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: WETH, tokenOut: USDC, amountIn: amountIn, fee: FEE, sqrtPriceLimitX96: 0
        });
        (uint256 quoterV2AmountOut,,,) = IQuoterV2(QUOTER_V2).quoteExactInputSingle(params);

        assertEq(ourQuote, quoterV2AmountOut, "UniswapV3QuoteSingle != QuoterV2");
    }

    function testFork_ProtocolFeeReducesAmountOut() public {
        uint256 amountIn = 1_000_000; // 1 USDC
        uint256 protocolFeeBps = 300; // 3%

        uint256 quoteNoFee = helper.getAmountOut(POOL, USDC, amountIn, 0);
        uint256 quoteWithFee = helper.getAmountOut(POOL, USDC, amountIn, protocolFeeBps);

        uint256 expectedWithFee = (quoteNoFee * (10_000 - protocolFeeBps)) / 10_000;
        assertEq(quoteWithFee, expectedWithFee, "protocol fee not applied");
    }
}
