/*
    Copyright 2021 Babylon Finance

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
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';

import {IHarvestVault} from '../../interfaces/external/harvest/IVault.sol';

/**
 * @title HarvestIntegration
 * @author Babylon Finance Protocol
 *
 * Harvest v2 Vault Integration
 */
contract HarvestVaultIntegration is PassiveIntegration {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyGovernance() {
        require(msg.sender == controller.owner(), 'Only governance can call this');
        _;
    }

    /* ============ State Variables ============ */

    mapping(address => address) public assetToVault;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _weth                         Address of the WETH ERC20
     */
    constructor(
        IBabController _controller,
        address _weth
    ) PassiveIntegration('harvestvaults', _weth, _controller) {
        assetToVault[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 0xab7FA2B2985BCcfC13c6D86b1D5A17486ab1e04C; // DAI
        assetToVault[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 0xFE09e53A81Fe2808bc493ea64319109B5bAa573e; // WETH
        assetToVault[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE; // USDC
        assetToVault[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 0x053c80eA73Dc6941F518a68E2FC52Ac45BDE7c9C; // USDT
        assetToVault[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599] = 0x5d9d25c7C457dD82fc8668FFC6B9746b674d4EcB; // WBTC
    }

    /* ============ External Functions ============ */

    // Governance function
    function updateVaultMapping(address _asset, address _vault) external onlyGovernance {
        assetToVault[_asset] = _vault;
    }

    /* ============ Internal Functions ============ */

    function _isInvestment(address _vault) internal view override returns (bool) {
        return IHarvestVault(_vault).underlying() != address(0);
    }

    function _getSpender(address _vault) internal view override returns (address) {
        return _vault;
    }

    function _getExpectedShares(address _vault, uint256 _amount)
        internal
        view
        override
        returns (uint256)
    {
        return _amount.preciseDiv(IHarvestVault(_vault).getPricePerFullShare());
    }

    function _getPricePerShare(address _vault) internal view override returns (uint256) {
        return IHarvestVault(_vault).getPricePerFullShare();
    }

    function _getInvestmentAsset(address _vault) internal view override returns (address) {
        return IHarvestVault(_vault).underlying();
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _investmentAddress              Address of the vault
     * hparam  _investmentTokensOut            Amount of investment tokens to send
     * hparam  _tokenIn                        Addresses of tokens to send to the investment
     * @param  _maxAmountIn                    Amounts of tokens to send to the investment
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getEnterInvestmentCalldata(
        address, /* _strategy */
        address _investmentAddress,
        uint256, /* _investmentTokensOut */
        address, /* _tokenIn */
        uint256 _maxAmountIn
    )
        internal
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('deposit(uint256)', _maxAmountIn);

        return (_investmentAddress, 0, methodData);
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _investmentAddress              Address of the investment
     * @param  _investmentTokensIn             Amount of investment tokens to receive
     * hparam  _tokenOut                       Addresses of tokens to receive
     * hparam  _minAmountOut                   Amounts of investment tokens to receive
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getExitInvestmentCalldata(
        address, /* _strategy */
        address _investmentAddress,
        uint256 _investmentTokensIn,
        address, /* _tokenOut */
        uint256 /* _minAmountOut */
    )
        internal
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('withdraw(uint256)', _investmentTokensIn);

        return (_investmentAddress, 0, methodData);
    }
}
