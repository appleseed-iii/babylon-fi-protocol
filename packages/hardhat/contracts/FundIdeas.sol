/*
    Copyright 2020 Babylon Finance.

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

// import "hardhat/console.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IWETH } from "./interfaces/external/weth/IWETH.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { IBabController } from "./interfaces/IBabController.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IClosedFund } from "./interfaces/IClosedFund.sol";

/**
 * @title FundIdeas
 * @author Babylon Finance
 *
 * Holds the investment ideas for a single fund.
 */
contract FundIdeas is ReentrancyGuard {
  using SafeCast for uint256;
  using SafeCast for int256;
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using PreciseUnitMath for int256;
  using PreciseUnitMath for uint256;

  /* ============ Events ============ */

  /* ============ Modifiers ============ */

  modifier onlyContributor(address payable _caller) {
    require(
        ERC20(address(fund)).balanceOf(_caller) > 0,
        "Only someone with the fund token can withdraw"
    );
    _;
  }

  /**
   * Throws if the sender is not a keeper in the protocol
   */
  modifier onlyKeeper() {
    require(controller.isValidKeeper(msg.sender), "Only a keeper can call this");
    _;
  }

  /**
   * Throws if the fund is not active
   */
  modifier onlyActive() {
    require(fund.active() == true, "Fund must be active");
    _;
  }

  /* ============ Structs ============ */

  struct InvestmentIdea {
    uint256 index;                     // Investment index (used for votes)
    address payable participant;       // Address of the participant that submitted the bet
    uint256 enteredAt;                 // Timestamp when the idea was submitted
    uint256 executedAt;                // Timestamp when the idea was executed
    uint256 exitedAt;                  // Timestamp when the idea was submitted
    uint256 stake;                     // Amount of stake (in reserve asset)
    uint256 capitalRequested;          // Amount of capital requested (in reserve asset)
    uint256 expectedReturn;            // Expect return by this investment idea
    address[] enterTokensNeeded;       // Positions that need to be taken prior to enter trade
    uint256[] enterTokensAmounts;      // Amount of these positions
    address[] voters;                  // Addresses with the voters
    uint256 duration;                  // Duration of the bet
    int256 totalVotes;                 // Total votes
    uint256 totalVoters;               // Total amount of participants that voted
    address integration;               // Address of the integration
    bytes enterPayload;                // Calldata to execute when entering
    bytes exitPayload;                 // Calldata to execute when exiting the trade
    bool finalized;                    // Flag that indicates whether we exited the idea
  }

  /* ============ State Variables ============ */

  uint8 constant MAX_IDEAS = 10;

  // Babylon Controller Address
  IBabController public controller;

  // Fund that these ideas belong to
  IClosedFund public fund;

  mapping(uint256 => mapping(address => int256)) internal votes;  // Investment idea votes from participants (can be negative if downvoting)

  uint256 currentMinStakeEpoch;        // Used to keep track of the min staked amount. An idea can only be submitted if there are less than 3 or above the limit
  uint256 currentMinStakeIndex;        // Index position of the investment idea with the lowest stake

  uint8 public maxIdeasPerEpoch = 3;
  uint256 public currentInvestmentsIndex = 1;
  uint8 public minVotersQuorum = 1;

  InvestmentIdea[MAX_IDEAS] investmentIdeasCurrentEpoch;
  InvestmentIdea[] investmentsExecuted;

  uint256 public ideaCreatorProfitPercentage = 15e16; // (0.01% = 1e14, 1% = 1e16)
  uint256 public ideaVotersProfitPercentage = 5e16; // (0.01% = 1e14, 1% = 1e16)
  uint256 public lastInvestmentExecutedAt; // Timestamp when the last investment was executed

  uint256 public fundDuration; // Initial duration of the fund
  uint256 public fundEpoch; // Set window of time to decide the next investment idea
  uint256 public fundDeliberationDuration; // Window for endorsing / downvoting an idea

  /* ============ Constructor ============ */

  /**
   * Before a fund is initialized, the fund ideas need to be created and passed to fund initialization.
   *
   * @param _fund                           Address of the fund
   * @param _controller                     Address of the controller
   * @param _fundEpoch                      Controls how often an investment idea can be executed
   * @param _fundDeliberationDuration       How long after the epoch has completed, people can curate before the top idea being executed
   */
  constructor(
    address _fund,
    address _controller,
    uint256 _fundEpoch,
    uint256 _fundDeliberationDuration,
    uint256 _ideaCreatorProfitPercentage,
    uint256 _ideaVotersProfitPercentage,
    uint8 _minVotersQuorum,
    uint8 _maxIdeasPerEpoch
  )
  {
    controller = IBabController(_controller);
    require(
        _fundEpoch <= controller.getMaxFundEpoch() && _fundEpoch >= controller.getMinFundEpoch() ,
        "Fund epoch must be within the range allowed by the protocol"
    );
    require(
        _fundDeliberationDuration <= controller.getMaxDeliberationPeriod() && _fundDeliberationDuration >= controller.getMinDeliberationPeriod() ,
        "Fund deliberation must be within the range allowed by the protocol"
    );
    require(_minVotersQuorum > 0, "You need at least one additional vote");
    require(controller.isSystemContract(_fund), "Must be a valid fund");
    require(_maxIdeasPerEpoch < MAX_IDEAS, "Number of ideas must be less than the limit");
    fund = IClosedFund(_fund);
    fundEpoch = _fundEpoch;
    fundDeliberationDuration = _fundDeliberationDuration;
    ideaCreatorProfitPercentage = _ideaCreatorProfitPercentage;
    ideaVotersProfitPercentage = _ideaVotersProfitPercentage;
    minVotersQuorum = _minVotersQuorum;
    maxIdeasPerEpoch = _maxIdeasPerEpoch;
    lastInvestmentExecutedAt = block.timestamp; // Start the counter for first epoch
  }


  /* ============ External Functions ============ */

  /**
   * Adds an investment idea to the contenders array for this epoch.
   * Investment stake is stored in the contract. (not converted to reserve asset).
   * If the array is already at the limit, replace the one with the lowest stake.
   * @param _capitalRequested              Capital requested denominated in the reserve asset
   * @param _stake                         Stake denominated in the reserve asset
   * @param _investmentDuration            Investment duration in seconds
   * @param _enterData                     Operation to perform to enter the investment
   * @param _exitData                      Operation to perform to exit the investment
   * @param _integration                   Address of the integration
   */
  function addInvestmentIdea(
    uint256 _capitalRequested,
    uint256 _stake,
    uint256 _investmentDuration,
    bytes memory _enterData,
    bytes memory _exitData,
    address _integration,
    uint256 _expectedReturn,
    address[] memory _enterTokensNeeded,
    uint256[] memory _enterTokensAmounts
  ) external onlyContributor(msg.sender) payable onlyActive {
    require(block.timestamp < lastInvestmentExecutedAt.add(fundEpoch), "Idea can only be suggested before the deliberation period");
    //require(fund.isValidIntegration(_integration), "Integration must be valid");
    require(_stake > 0, "Stake amount must be greater than 0");
    require(_capitalRequested > 0, "Capital requested amount must be greater than 0");
    require(_investmentDuration > 1 hours, "Investment duration must be greater than an hour");
    uint256 liquidReserveAsset = fund.getPositionBalance(fund.getReserveAsset()).toUint256();
    // TODO: loop over previous investments as well
    //if (investmentsExecuted[investmentsExecuted.length - 1].duration < lastInvestmentExecutedAt.add(fundEpoch)) {
    //  liquidReserveAsset = liquidReserveAsset.add(investmentsExecuted[investmentsExecuted.length - 1].capitalRequested);
    //}
    require(_capitalRequested <= liquidReserveAsset, "The capital requested is greater than the capital available");
    require(investmentIdeasCurrentEpoch.length < maxIdeasPerEpoch || _stake > currentMinStakeEpoch, "Not enough stake to add the idea");
    uint ideaIndex = investmentIdeasCurrentEpoch.length;
    if (ideaIndex >= maxIdeasPerEpoch) {
      ideaIndex = currentMinStakeIndex;
    }
    // Check than enter and exit data call integrations
    InvestmentIdea storage idea = investmentIdeasCurrentEpoch[ideaIndex];
    idea.index = currentInvestmentsIndex;
    idea.integration = _integration;
    idea.participant = msg.sender;
    idea.capitalRequested = _capitalRequested;
    idea.enteredAt = block.timestamp;
    idea.stake = _stake;
    idea.duration = _investmentDuration;
    idea.enterPayload = _enterData;
    idea.exitPayload = _exitData;
    idea.enterTokensNeeded = _enterTokensNeeded;
    idea.enterTokensAmounts = _enterTokensAmounts;
    idea.expectedReturn = _expectedReturn;
    currentInvestmentsIndex ++;
  }

  /**
   * Curates an investment idea from the contenders array for this epoch.
   * This can happen at any time. As long as there are investment ideas.
   * @param _ideaIndex                The position of the idea index in the array for the current epoch
   * @param _amount                   Amount to curate, positive to endorse, negative to downvote
   * TODO: Meta Transaction
   */
  function curateInvestmentIdea(uint8 _ideaIndex, int256 _amount) external onlyContributor(msg.sender) onlyActive {
    require(investmentIdeasCurrentEpoch.length > _ideaIndex, "The idea index does not exist");
    require(_amount.toUint256() < fund.balanceOf(msg.sender), "Participant does not have enough balance");
    InvestmentIdea storage idea = investmentIdeasCurrentEpoch[_ideaIndex];
    uint256 totalVotesUser = 0;
    for (uint8 i = 0; i < investmentIdeasCurrentEpoch.length; i++) {
      totalVotesUser = totalVotesUser.add(votes[idea.index][msg.sender].toUint256());
    }
    require(totalVotesUser.add(_amount.toUint256()) < fund.balanceOf(msg.sender), "Participant does not have enough balance");
    if (votes[idea.index][msg.sender] == 0) {
      idea.totalVoters++;
      idea.voters = [msg.sender];
    } else {
      idea.voters.push(msg.sender);
    }
    votes[idea.index][msg.sender] = votes[idea.index][msg.sender].add(_amount);
    idea.totalVotes.add(_amount);
  }

  /**
   * Executes the top investment idea for this epoch.
   * We enter into the investment and add it to the executed ideas array.
   */
  function executeTopInvestment() external onlyKeeper onlyActive {
    require(block.timestamp > lastInvestmentExecutedAt.add(fundEpoch).add(fundDeliberationDuration), "Idea can only be executed after the minimum period has elapsed");
    require(investmentIdeasCurrentEpoch.length > 0, "There must be an investment idea ready to execute");
    uint8 topIdeaIndex = getCurrentTopInvestmentIdea();
    require(topIdeaIndex < investmentIdeasCurrentEpoch.length, "No idea available to execute");
    InvestmentIdea storage idea = investmentIdeasCurrentEpoch[topIdeaIndex];
    // Execute enter trade
    bytes memory _data = idea.enterPayload;
    fund.callIntegration(idea.integration, 0, _data, idea.enterTokensNeeded, idea.enterTokensAmounts);
    // Push the trade to the investments executed
    investmentsExecuted[investmentsExecuted.length] = idea;
    // Clear investment ideas
    delete investmentIdeasCurrentEpoch;
    // Restarts the epoc counter
    lastInvestmentExecutedAt = block.timestamp;
    idea.executedAt = block.timestamp;
  }

  /**
   * Exits from an executed investment.
   * Sends rewards to the person that created the idea, the voters, and the rest to the fund.
   * If there are profits
   * Updates the reserve asset position accordingly.
   */
  function finalizeInvestment(uint _ideaIndex) external onlyKeeper nonReentrant onlyActive {
    require(investmentsExecuted.length > _ideaIndex, "This idea index does not exist");
    InvestmentIdea storage idea = investmentsExecuted[_ideaIndex];
    require(block.timestamp > lastInvestmentExecutedAt.add(fundEpoch).add(idea.duration), "Idea can only be executed after the minimum period has elapsed");
    require(!idea.finalized, "This investment was already exited");
    address[] memory _tokensNeeded;
    uint256[] memory _tokenAmounts;
    // Execute exit trade
    bytes memory _data = idea.exitPayload;
    address reserveAsset = fund.getReserveAsset();
    uint256 reserveAssetBeforeExiting = fund.getPositionBalance(reserveAsset).toUint256();
    fund.callIntegration(idea.integration, 0, _data, _tokensNeeded, _tokenAmounts);
    // Exchange the tokens back to the reserve asset
    bytes memory _emptyTradeData;
    for (uint i = 0; i < idea.enterTokensNeeded.length; i++) {
      if (idea.enterTokensNeeded[i] != reserveAsset) {
        uint pricePerTokenUnit = _getPrice(reserveAsset, idea.enterTokensNeeded[i]);
        // TODO: The actual amount must be supposedly higher when we exit
        fund.tradeFromInvestmentIdea("kyber", idea.enterTokensNeeded[i], idea.enterTokensAmounts[i], reserveAsset, idea.enterTokensAmounts[i].preciseDiv(pricePerTokenUnit), _emptyTradeData);
      }
    }
    uint256 capitalReturned = fund.getPositionBalance(reserveAsset).toUint256().sub(reserveAssetBeforeExiting);
    // Mark as finalized
    idea.finalized = true;
    idea.exitedAt = block.timestamp;
    // Transfer rewards and update positions
     _transferIdeaRewards(_ideaIndex, capitalReturned);
  }

  /* ============ External Getter Functions ============ */

  /**
   * Gets the index of the top investment idea in this epoch
   * Uses the stake, the number of voters and the total weight behind the idea.
   *
   * @return  uint8        Top Idea index. Returns the max length + 1 if none.
   */
  function getCurrentTopInvestmentIdea() public view returns (uint8) {
    uint256 maxScore = 0;
    uint8 indexResult = maxIdeasPerEpoch + 1;
    for (uint8 i = 0; i < investmentIdeasCurrentEpoch.length; i++) {
      InvestmentIdea memory idea = investmentIdeasCurrentEpoch[i];
      // TODO: tweak this formula
      if (idea.totalVotes > 0 && idea.totalVoters >= minVotersQuorum) {
        uint256 currentScore = idea.stake.mul(idea.totalVotes.toUint256()).mul(idea.totalVoters);
        if (currentScore > maxScore) {
          indexResult = i;
        }
      }
    }
    return indexResult;
  }

  /* ============ Internal Functions ============ */

  function _transferIdeaRewards(uint _ideaIndex, uint capitalReturned) internal {
    address reserveAsset = fund.getReserveAsset();
    uint256 reserveAssetDelta = 0;
    InvestmentIdea storage idea = investmentsExecuted[_ideaIndex];
    // Idea returns were positive
    if (capitalReturned > idea.capitalRequested) {
      uint256 profits = capitalReturned - idea.capitalRequested; // in reserve asset (weth)
      // Send stake back to the creator
      idea.participant.transfer(idea.stake);
      uint256 ideatorProfits = ideaCreatorProfitPercentage.preciseMul(profits);
      // Send rewards to the creator
      ERC20(reserveAsset).transfer(
        idea.participant,
        ideatorProfits
      );
      reserveAssetDelta.add(uint256(-ideatorProfits));
      uint256 votersProfits = ideaVotersProfitPercentage.preciseMul(profits);
      // Send rewards to voters that voted in favor
      for (uint256 i = 0; i < idea.voters.length; i++) {
        int256 voterWeight = votes[_ideaIndex][idea.voters[i]];
        if (voterWeight > 0) {
          ERC20(reserveAsset).transfer(
            idea.voters[i],
            votersProfits.mul(voterWeight.toUint256()).div(idea.totalVotes.toUint256())
          );
        }
      }
      reserveAssetDelta.add(uint256(-votersProfits));
    } else {
      // Returns were negative
      uint256 stakeToSlash = idea.stake;
      if (capitalReturned.add(idea.stake) > idea.capitalRequested) {
        stakeToSlash = capitalReturned.add(idea.stake).sub(idea.capitalRequested);
      }
      // We slash and add to the fund the stake from the creator
      IWETH(fund.weth()).deposit{value: stakeToSlash}();
      reserveAssetDelta.add(stakeToSlash);
      uint256 votersRewards = ideaVotersProfitPercentage.preciseMul(stakeToSlash);
      // Send rewards to voters that voted against
      for (uint256 i = 0; i < idea.voters.length; i++) {
        int256 voterWeight = votes[_ideaIndex][idea.voters[i]];
        if (voterWeight < 0) {
          ERC20(reserveAsset).transfer(
            idea.voters[i],
            votersRewards.mul(voterWeight.toUint256()).div(idea.totalVotes.toUint256())
          );
        }
      }
      reserveAssetDelta.add(uint256(-stakeToSlash));
    }
    // Updates reserve asset position in the fund
    uint256 _newTotal = fund.getPositionBalance(reserveAsset).add(int256(reserveAssetDelta)).toUint256();
    fund.calculateAndEditPosition(reserveAsset, _newTotal, reserveAssetDelta, 0);
  }

  function _getPrice(address _assetOne, address _assetTwo) internal view returns (uint256) {
    IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
    return oracle.getPrice(_assetOne, _assetTwo);
  }

}
