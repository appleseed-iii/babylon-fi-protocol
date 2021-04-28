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

/**
 * @title IBabController
 * @author Babylon Finance
 *
 * Interface for interacting with BabController
 */
interface IBabController {
    /* ============ Functions ============ */

    function createGarden(
        address _reserveAsset,
        string memory _name,
        string memory _symbol,
        string memory _tokenURI,
        uint256 _seed,
        uint256[] calldata _gardenParams
    ) external payable returns (address);

    function removeGarden(address _garden) external;

    function addReserveAsset(address _reserveAsset) external;

    function removeReserveAsset(address _reserveAsset) external;

    function disableGarden(address _garden) external;

    function editPriceOracle(address _priceOracle) external;

    function editIshtarGate(address _ishtarGate) external;

    function editGardenValuer(address _gardenValuer) external;

    function editRewardsDistributor(address _rewardsDistributor) external;

    function editTreasury(address _newTreasury) external;

    function editGardenFactory(address _newGardenFactory) external;

    function editStrategyFactory(uint8 _strategyKind, address _newStrategyFactory) external;

    function addIntegration(string memory _name, address _integration) external;

    function editIntegration(string memory _name, address _integration) external;

    function removeIntegration(string memory _name) external;

    function addKeeper(address _keeper) external;

    function addKeepers(address[] memory _keepers) external;

    function removeKeeper(address _keeper) external;

    function enableGardenTokensTransfers() external;

    function enableBABLTokensTransfers() external;

    function disableBABLTokensTransfers() external;

    function enableBABLMiningProgram() external;

    function editLiquidityMinimum(uint256 _minRiskyPairLiquidityEth) external;

    function owner() external view returns (address);

    function priceOracle() external view returns (address);

    function gardenValuer() external view returns (address);

    function rewardsDistributor() external view returns (address);

    function gardenFactory() external view returns (address);

    function treasury() external view returns (address);

    function ishtarGate() external view returns (address);

    function protocolDepositGardenTokenFee() external view returns (uint256);

    function protocolWithdrawalGardenTokenFee() external view returns (uint256);

    function gardenTokensTransfersEnabled() external view returns (bool);

    function bablTokensTransfersEnabled() external view returns (bool);

    function bablMiningProgramEnabled() external view returns (bool);

    function getProfitSharing()
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function getBABLSharing()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    function getStrategyFactory(uint8 _strategyKind) external view returns (address);

    function getGardens() external view returns (address[] memory);

    function isGarden(address _garden) external view returns (bool);

    function getIntegrationByName(string memory _name) external view returns (address);

    function getIntegrationWithHash(bytes32 _nameHashP) external view returns (address);

    function isValidReserveAsset(address _reserveAsset) external view returns (bool);

    function isValidKeeper(address _keeper) external view returns (bool);

    function isSystemContract(address _contractAddress) external view returns (bool);

    function isValidIntegration(string memory _name, address _integration) external view returns (bool);

    function getMinCooldownPeriod() external view returns (uint256);

    function getMaxCooldownPeriod() external view returns (uint256);

    function protocolPerformanceFee() external view returns (uint256);

    function protocolManagementFee() external view returns (uint256);

    function minRiskyPairLiquidityEth() external view returns (uint256);

    function getUniswapFactory() external view returns (address);
}
