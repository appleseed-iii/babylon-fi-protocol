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
pragma solidity 0.7.4;

import {IGarden} from './IGarden.sol';
import {IBabController} from './IBabController.sol';

/**
 * @title IStrategyNFT
 * @author Babylon Finance
 *
 * Interface for operating with a Strategy NFT.
 */
interface IStrategyNFT {
    function initialize(
        address _controller,
        address _strategy,
        string memory _name,
        string memory _symbol
    ) external;

    function grantStrategyNFT(address _user, string memory _tokenURI) external returns (uint256);

    function updateStrategyURI(string memory _tokenURI) external;
}
