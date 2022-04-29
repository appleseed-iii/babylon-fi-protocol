// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {ITradeIntegration} from './ITradeIntegration.sol';
import {IStrategy, TradeInfo} from './IStrategy.sol';

/**
 * @title IIshtarGate
 * @author Babylon Finance
 *
 * Interface for interacting with the Gate Guestlist NFT
 */
interface IMasterSwapper {
    /* ============ Functions ============ */

    function trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity,
        TradeInfo memory _tradeInfo
    ) external returns (uint256, TradeInfo memory);

    function isTradeIntegration(address _integration) external view returns (bool);
}
