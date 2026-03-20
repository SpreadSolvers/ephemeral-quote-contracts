// SPDX-License-Identifier: LicenseRef-CICADA-Proprietary
// SPDX-FileCopyrightText: (c) 2024 Cicada Software, CICADA DMCC. All rights reserved.
pragma solidity ^0.8.24;

import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/**
 * @notice Minimal interface for Uniswap V4 PositionManager.
 * @dev Used to fetch poolManager and poolKey by poolId for quoting.
 */
interface IPositionManager {
    function poolManager() external view returns (address);

    function poolKeys(bytes25 poolId)
        external
        view
        returns (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks);
}
