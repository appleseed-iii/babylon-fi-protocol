// SPDX-License-Identifier: Apache-2.0


pragma solidity 0.8.9;

/**
 * @title IOracleAdapter
 * @author Babylon Finance
 *
 * Interface for calling an oracle adapter.
 */
interface IUniswapAnchoredView {
    function price(string memory symbol) external view returns (uint256);
}
