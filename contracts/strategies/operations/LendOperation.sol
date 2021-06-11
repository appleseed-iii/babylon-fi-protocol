/*
    Copyright 2021 Babylon Finance.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.7.6;
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Operation} from './Operation.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {ILendIntegration} from '../../interfaces/ILendIntegration.sol';

/**
 * @title LendOperatin
 * @author Babylon Finance
 *
 * Executes a lend operation
 */
contract LendOperation is Operation {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _controller) Operation(_name, _controller) {}

    /**
     * Sets operation data for the lend operation
     *
     * @param _data                   Operation data
     */
    function validateOperation(
        address _data,
        IGarden _garden,
        address, /* _integration */
        uint256 /* _index */
    ) external view override onlyStrategy {}

    /**
     * Executes the lend operation
     * @param _capital      Amount of capital received from the garden
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8, /* _assetStatus */
        address _data,
        IGarden, /* _garden */
        address _integration
    )
        external
        override
        onlyStrategy
        returns (
            address,
            uint256,
            uint8
        )
    {
        address assetToken = _data;
        if (assetToken != _asset) {
            IStrategy(msg.sender).trade(_asset, _capital, assetToken);
        }
        uint256 numTokensToSupply = IERC20(assetToken).balanceOf(msg.sender);
        uint256 exactAmount = ILendIntegration(_integration).getExpectedShares(assetToken, numTokensToSupply);
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
        ILendIntegration(_integration).supplyTokens(msg.sender, assetToken, numTokensToSupply, minAmountExpected);
        return (assetToken, numTokensToSupply, 1); // put as collateral
    }

    /**
     * Exits the lend operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        uint256 _percentage,
        address _data,
        IGarden _garden,
        address _integration
    ) external override onlyStrategy {
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        address assetToken = _data;
        uint256 numTokensToRedeem =
            IERC20(ILendIntegration(_integration).getInvestmentToken(assetToken)).balanceOf(msg.sender).preciseMul(
                _percentage
            );
        ILendIntegration(_integration).redeemTokens(
            msg.sender,
            assetToken,
            numTokensToRedeem,
            ILendIntegration(_integration).getExchangeRatePerToken(assetToken).mul(
                numTokensToRedeem.sub(numTokensToRedeem.preciseMul(SLIPPAGE_ALLOWED))
            )
        );
        if (assetToken != _garden.reserveAsset()) {
            IStrategy(msg.sender).trade(assetToken, IERC20(assetToken).balanceOf(msg.sender), _garden.reserveAsset());
        }
    }

    /**
     * Gets the NAV of the lend op in the reserve asset
     *
     * @return _nav           NAV of the strategy
     */
    function getNAV(
        address _assetToken,
        IGarden _garden,
        address _integration
    ) external view override onlyStrategy returns (uint256) {
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return 0;
        }
        uint256 numTokensToRedeem =
            IERC20(ILendIntegration(_integration).getInvestmentToken(_assetToken)).balanceOf(msg.sender);
        uint256 assetTokensAmount =
            ILendIntegration(_integration).getExchangeRatePerToken(_assetToken).mul(numTokensToRedeem);
        uint256 price = _getPrice(_garden.reserveAsset(), _assetToken);
        uint256 NAV = SafeDecimalMath.normalizeDecimals(_assetToken, assetTokensAmount).preciseDiv(price);
        require(NAV != 0, 'NAV has to be bigger 0');
        return NAV;
    }
}
