// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice BSC fork: same pool / token / amount as `quote` CLI repro (PancakeSwap V3 pool).
/// @dev Set BSC_RPC_URL to run. `BSC_FORK_BLOCK=0` (default) uses latest head (works on most public RPCs).
///      Set `BSC_FORK_BLOCK` to a positive number for a pinned fork (needs archive / indexed history).

import {Test} from "forge-std/Test.sol";
import {UniswapV3QuoteSingle} from "../src/UniswapV3QuoteSingle.sol";
import {UniswapV3QuoteSingleEphemeral} from "../src/UniswapV3QuoteSingleEphemeral.sol";

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
            require(reason.length >= 4, "QuoteSingleHelper: no revert data");

            bytes4 selector = bytes4(reason);
            if (
                selector == UniswapV3QuoteSingle.InsufficientLiquidity.selector
                    || selector == UniswapV3QuoteSingle.PartialFill.selector
            ) {
                assembly {
                    revert(add(reason, 0x20), mload(reason))
                }
            }

            require(reason.length >= 36, "QuoteSingleHelper: unexpected revert data");
            bytes memory payload = new bytes(reason.length - 4);
            for (uint256 j; j < payload.length; j++) {
                payload[j] = reason[j + 4];
            }
            amountOut = abi.decode(payload, (uint256));
        }
    }
}

contract UniswapV3QuoteSingleBscForkTest is Test {
    QuoteSingleHelper public helper;

    /// CLI repro: `quote <pool> uni-v3 <token_in> 500000000000000000000 <rpc>`
    address constant POOL = 0x8f889728C2a879B15936eecC38A61F03fCDc6818;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant TOKEN_OUT = 0xb150e91Cb40909F47d45115eE9E90667D807464B;

    address constant QUOTER_V2_BSC = 0xB048Bbc1Ee6b733FFfCFb9e9CeF7375518e25997;
    uint24 constant FEE = 100; // pool fee tier

        function setUp() public {
        string memory rpcUrl = vm.envOr("BSC_RPC_URL", string(""));
        vm.skip(bytes(rpcUrl).length == 0);
        uint256 forkBlock = vm.envOr("BSC_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, forkBlock);
        }
        helper = new QuoteSingleHelper();
    }

    function testFork_Bsc_CliCase_Usdt500_MatchesQuoterV2() public {
        uint256 amountIn = 500 ether;

        uint256 ourQuote = helper.getAmountOut(POOL, USDT, amountIn, 0);

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: USDT,
            tokenOut: TOKEN_OUT,
            amountIn: amountIn,
            fee: FEE,
            sqrtPriceLimitX96: 0
        });
        (uint256 quoterV2AmountOut,,,) = IQuoterV2(QUOTER_V2_BSC).quoteExactInputSingle(params);

        assertEq(ourQuote, quoterV2AmountOut, "UniswapV3QuoteSingle != Pancake QuoterV2 on BSC");
    }

    /// @dev Same code path as Rust CLI: CREATE `UniswapV3QuoteSingleEphemeral` (nested deploy + quote).
    ///      If this passes but `cargo test --ignored` ephemeral test fails, the node is omitting revert data on eth_call.
    function testFork_Bsc_EphemeralDeploy_MatchesQuoterV2() public {
        uint256 amountIn = 500 ether;

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: USDT,
            tokenOut: TOKEN_OUT,
            amountIn: amountIn,
            fee: FEE,
            sqrtPriceLimitX96: 0
        });
        (uint256 quoterV2AmountOut,,,) = IQuoterV2(QUOTER_V2_BSC).quoteExactInputSingle(params);

        vm.expectRevert(
            abi.encodeWithSelector(UniswapV3QuoteSingle.AmountOut.selector, quoterV2AmountOut)
        );
        new UniswapV3QuoteSingleEphemeral(POOL, USDT, amountIn, 0);
    }
}
