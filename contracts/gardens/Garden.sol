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


import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';

import {Errors, _require} from '../lib/BabylonErrors.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';

import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IStrategyFactory} from '../interfaces/IStrategyFactory.sol';
import {IGardenValuer} from '../interfaces/IGardenValuer.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IGardenNFT} from '../interfaces/IGardenNFT.sol';
import {IIshtarGate} from '../interfaces/IIshtarGate.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';

/**
 * @title BaseGarden
 * @author Babylon Finance
 *
 * Class that holds common garden-related state and functions
 */
contract Garden is ERC20Upgradeable, ReentrancyGuard, IGarden {
    using SafeCast for int256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using SafeDecimalMath for int256;

    using SafeCast for uint256;
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    using Address for address;
    using AddressArrayUtils for address[];

    using SafeERC20 for IERC20;

    /* ============ Events ============ */
    event GardenDeposit(address indexed _to, uint256 reserveToken, uint256 reserveTokenQuantity, uint256 timestamp);
    event GardenWithdrawal(
        address indexed _from,
        address indexed _to,
        uint256 reserveToken,
        uint256 reserveTokenQuantity,
        uint256 timestamp
    );
    event AddStrategy(address indexed _strategy, string _name, uint256 _expectedReturn);

    event RewardsForContributor(address indexed _contributor, uint256 indexed _amount);
    event BABLRewardsForContributor(address indexed _contributor, uint256 _rewards);

    /* ============ State Constants ============ */

    // Wrapped ETH address
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 private constant EARLY_WITHDRAWAL_PENALTY = 5e16;
    uint256 private constant MAX_TOTAL_STRATEGIES = 20; // Max number of strategies
    uint256 private constant TEN_PERCENT = 1e17;
    // Window of time after an investment strategy finishes when the capital is available for withdrawals
    uint256 private constant withdrawalWindowAfterStrategyCompletes = 7 days;

    /* ============ Structs ============ */

    struct Contributor {
        uint256 lastDepositAt;
        uint256 initialDepositAt;
        uint256 claimedAt;
        uint256 claimedBABL;
        uint256 claimedRewards;
        uint256 withdrawnSince;
        uint256 totalDeposits;
    }

    /* ============ State Variables ============ */

    // Reserve Asset of the garden
    address public override reserveAsset;

    // Address of the controller
    address public override controller;

    // Address of the rewards distributor
    IRewardsDistributor private rewardsDistributor;

    // The person that creates the garden
    address public override creator;
    // Whether the garden is currently active or not
    bool public override active;
    bool public override guestListEnabled;

    // Keeps track of the reserve balance. In case we receive some through other means
    uint256 public override principal;
    uint256 public override reserveAssetRewardsSetAside;
    uint256 public override reserveAssetPrincipalWindow;
    int256 public override absoluteReturns; // Total profits or losses of this garden

    // Indicates the minimum liquidity the asset needs to have to be tradable by this garden
    uint256 public override minLiquidityAsset;

    uint256 public override depositHardlock; // Window of time after deposits when withdraws are disabled for that user
    uint256 public override withdrawalsOpenUntil; // Indicates until when the withdrawals are open and the ETH is set aside

    // Contributors
    mapping(address => Contributor) private contributors;
    uint256 public override totalContributors;
    uint256 public override maxContributors;
    uint256 public override maxDepositLimit; // Limits the amount of deposits

    uint256 public override gardenInitializedAt; // Garden Initialized at timestamp
    // Number of garden checkpoints used to control de garden power and each contributor power with accuracy avoiding flash loans and related attack vectors
    uint256 private pid;

    // Min contribution in the garden
    uint256 public override minContribution; //wei
    uint256 private minGardenTokenSupply; // DEPRECATED

    // Strategies variables
    uint256 public override totalStake;
    uint256 public override minVotesQuorum = TEN_PERCENT; // 10%. (0.01% = 1e14, 1% = 1e16)
    uint256 public override minVoters;
    uint256 public override minStrategyDuration; // Min duration for an strategy
    uint256 public override maxStrategyDuration; // Max duration for an strategy
    // Window for the strategy to cooldown after approval before receiving capital
    uint256 public override strategyCooldownPeriod;

    address[] private strategies; // Strategies that are either in candidate or active state
    address[] private finalizedStrategies; // Strategies that have finalized execution
    mapping(address => bool) public override strategyMapping;
    mapping(address => bool) public override isGardenStrategy; // Security control mapping

    // Keeper debt in reserve asset if any, repaid upon every strategy finalization
    uint256 public keeperDebt;

    /* ============ Modifiers ============ */

    function _onlyContributor() private view {
        _onlyUnpaused();
        _require(balanceOf(msg.sender) > 0, Errors.ONLY_CONTRIBUTOR);
    }

    function _onlyUnpaused() private view {
        // Do not execute if Globally or individually paused
        _require(!IBabController(controller).isPaused(address(this)), Errors.ONLY_UNPAUSED);
    }

    /**
     * Throws if the sender is not an strategy of this garden
     */
    function _onlyStrategy() private view {
        _onlyUnpaused();
        _require(strategyMapping[msg.sender], Errors.ONLY_STRATEGY);
    }

    /**
     * Throws if the garden is not active
     */
    function _onlyActive() private view {
        _onlyUnpaused();
        _require(active, Errors.ONLY_ACTIVE);
    }

    /* ============ Constructor ============ */

    /**
     * When a new Garden is created.
     * All parameter validations are on the BabController contract. Validations are performed already on the
     * BabController.
     * WARN: If the reserve Asset is different than WETH the gardener needs to have approved the controller.
     *
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _controller             Address of the controller
     * @param _creator                Address of the creator
     * @param _name                   Name of the Garden
     * @param _symbol                 Symbol of the Garden
     * @param _gardenParams           Array of numeric garden params
     * @param _initialContribution    Initial Contribution by the Gardener
     */
    function initialize(
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol,
        uint256[] calldata _gardenParams,
        uint256 _initialContribution
    ) public payable override initializer {
        _require(bytes(_name).length < 50, Errors.NAME_TOO_LONG);
        _require(
            _creator != address(0) && _controller != address(0) && ERC20Upgradeable(_reserveAsset).decimals() > 0,
            Errors.ADDRESS_IS_ZERO
        );
        _require(_gardenParams.length == 9, Errors.GARDEN_PARAMS_LENGTH);
        _require(IBabController(_controller).isValidReserveAsset(_reserveAsset), Errors.MUST_BE_RESERVE_ASSET);
        __ERC20_init(_name, _symbol);

        controller = _controller;
        reserveAsset = _reserveAsset;
        creator = _creator;
        maxContributors = IBabController(_controller).maxContributorsPerGarden();
        rewardsDistributor = IRewardsDistributor(IBabController(controller).rewardsDistributor());
        _require(address(rewardsDistributor) != address(0), Errors.ADDRESS_IS_ZERO);
        guestListEnabled = true;

        _start(
            _initialContribution,
            _gardenParams[0],
            _gardenParams[1],
            _gardenParams[2],
            _gardenParams[3],
            _gardenParams[4],
            _gardenParams[5],
            _gardenParams[6],
            _gardenParams[7],
            _gardenParams[8]
        );
        active = true;
    }

    /* ============ External Functions ============ */

    /**
     * FUND LEAD ONLY.  Starts the Garden with allowed reserve assets,
     * fees and issuance premium. Only callable by the Garden's creator
     *
     * @param _creatorDeposit                       Deposit by the creator
     * @param _maxDepositLimit                      Max deposit limit
     * @param _minLiquidityAsset                    Number that represents min amount of liquidity denominated in ETH
     * @param _depositHardlock                      Number that represents the time deposits are locked for an user after he deposits
     * @param _minContribution                      Min contribution to the garden
     * @param _strategyCooldownPeriod               How long after the strategy has been activated, will it be ready to be executed
     * @param _minVotesQuorum                       Percentage of votes needed to activate an strategy (0.01% = 1e14, 1% = 1e16)
     * @param _minStrategyDuration                  Min duration of an strategy
     * @param _maxStrategyDuration                  Max duration of an strategy
     * @param _minVoters                            The minimum amount of voters needed for quorum
     */
    function _start(
        uint256 _creatorDeposit,
        uint256 _maxDepositLimit,
        uint256 _minLiquidityAsset,
        uint256 _depositHardlock,
        uint256 _minContribution,
        uint256 _strategyCooldownPeriod,
        uint256 _minVotesQuorum,
        uint256 _minStrategyDuration,
        uint256 _maxStrategyDuration,
        uint256 _minVoters
    ) private {
        _require(_minContribution > 0 && _creatorDeposit >= _minContribution, Errors.MIN_CONTRIBUTION);
        _require(
            _minLiquidityAsset >= IBabController(controller).minLiquidityPerReserve(reserveAsset),
            Errors.MIN_LIQUIDITY
        );
        _require(
            _creatorDeposit <= _maxDepositLimit && _maxDepositLimit <= (reserveAsset == WETH ? 1e22 : 1e25),
            Errors.MAX_DEPOSIT_LIMIT
        );
        _require(_depositHardlock > 0, Errors.DEPOSIT_HARDLOCK);
        _require(
            _strategyCooldownPeriod <= IBabController(controller).getMaxCooldownPeriod() &&
                _strategyCooldownPeriod >= IBabController(controller).getMinCooldownPeriod(),
            Errors.NOT_IN_RANGE
        );
        _require(_minVotesQuorum >= TEN_PERCENT && _minVotesQuorum <= TEN_PERCENT.mul(5), Errors.VALUE_TOO_LOW);
        _require(
            _maxStrategyDuration >= _minStrategyDuration &&
                _minStrategyDuration >= 1 days &&
                _maxStrategyDuration <= 500 days,
            Errors.DURATION_RANGE
        );
        _require(_minVoters >= 1 && _minVoters < 10, Errors.MIN_VOTERS_CHECK);
        minContribution = _minContribution;
        strategyCooldownPeriod = _strategyCooldownPeriod;
        minVotesQuorum = _minVotesQuorum;
        minVoters = _minVoters;
        minStrategyDuration = _minStrategyDuration;
        maxStrategyDuration = _maxStrategyDuration;
        maxDepositLimit = _maxDepositLimit;
        gardenInitializedAt = block.timestamp;
        minLiquidityAsset = _minLiquidityAsset;
        depositHardlock = _depositHardlock;
    }

    /**
     * Deposits the reserve asset into the garden and mints the Garden token of the given quantity
     * to the specified _to address.
     * WARN: If the reserve Asset is different than WETH the sender needs to have approved the garden.
     *
     * @param _reserveAssetQuantity  Quantity of the reserve asset that are received
     * @param _minGardenTokenReceiveQuantity   Min quantity of Garden token to receive after issuance
     * @param _to                   Address to mint Garden tokens to
     * @param _mintNft              Whether to mint NFT or not
     */
    function deposit(
        uint256 _reserveAssetQuantity,
        uint256 _minGardenTokenReceiveQuantity,
        address _to,
        bool _mintNft
    ) external payable override nonReentrant {
        _onlyActive();
        _require(
            !guestListEnabled ||
                IIshtarGate(IBabController(controller).ishtarGate()).canJoinAGarden(address(this), msg.sender) ||
                creator == _to,
            Errors.USER_CANNOT_JOIN
        );
        // if deposit limit is 0, then there is no deposit limit
        if (maxDepositLimit > 0) {
            _require(principal.add(_reserveAssetQuantity) <= maxDepositLimit, Errors.MAX_DEPOSIT_LIMIT);
        }

        _require(totalContributors <= maxContributors, Errors.MAX_CONTRIBUTORS);
        _require(_reserveAssetQuantity >= minContribution, Errors.MIN_CONTRIBUTION);

        // If reserve asset is WETH wrap it
        uint256 reserveAssetBalance = IERC20(reserveAsset).balanceOf(address(this));

        if (reserveAsset == WETH && msg.value > 0) {
            IWETH(WETH).deposit{value: msg.value}();
        } else {
            // Transfer ERC20 to the garden
            IERC20(reserveAsset).safeTransferFrom(msg.sender, address(this), _reserveAssetQuantity);
        }
        // Make sure we received the reserve asset
        _require(
            IERC20(reserveAsset).balanceOf(address(this)).sub(reserveAssetBalance) == _reserveAssetQuantity,
            Errors.MSG_VALUE_DO_NOT_MATCH
        );

        // gardenTokenQuantity has to be at least _minGardenTokenReceiveQuantity
        _require(_reserveAssetQuantity >= _minGardenTokenReceiveQuantity, Errors.RECEIVE_MIN_AMOUNT);

        uint256 previousBalance = balanceOf(_to);

        _mint(_to, getGardenTokenMintQuantity(_reserveAssetQuantity, true));
        _updateContributorDepositInfo(_to, previousBalance, _reserveAssetQuantity);
        principal = principal.add(_reserveAssetQuantity);

        // Mint the garden NFT
        if (_mintNft) {
            IGardenNFT(IBabController(controller).gardenNFT()).grantGardenNFT(_to);
        }

        emit GardenDeposit(_to, msg.value, _reserveAssetQuantity, block.timestamp);
    }

    /**
     * Withdraws the ETH relative to the token participation in the garden and sends it back to the sender.
     * ATTENTION. Do not call withPenalty unless certain. If penalty is set, it will be applied regardless of the garden state.
     * It is advised to first try to withdraw with no penalty and it this reverts then try to with penalty.
     *
     * @param _gardenTokenQuantity           Quantity of the garden token to withdrawal
     * @param _minReserveReceiveQuantity     Min quantity of reserve asset to receive
     * @param _to                            Address to send component assets to
     * @param _withPenalty                   Whether or not this is an immediate withdrawal
     * @param _unwindStrategy                Strategy to unwind
     */
    function withdraw(
        uint256 _gardenTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to,
        bool _withPenalty,
        address _unwindStrategy
    ) external override nonReentrant {
        _onlyContributor();
        // Flashloan protection
        _require(
            block.timestamp.sub(contributors[msg.sender].lastDepositAt) >= depositHardlock,
            Errors.DEPOSIT_HARDLOCK
        );
        // Withdrawal amount has to be equal or less than msg.sender balance minus the locked balance
        uint256 lockedAmount = getLockedBalance(msg.sender);
        _require(_gardenTokenQuantity <= balanceOf(msg.sender).sub(lockedAmount), Errors.TOKENS_STAKED); // Strategists cannot withdraw locked stake while in active strategies

        uint256 outflow = _getWithdrawalReserveQuantity(reserveAsset, _gardenTokenQuantity);

        // if withPenaltiy then unwind strategy
        if (_withPenalty) {
            outflow = outflow.sub(outflow.preciseMul(EARLY_WITHDRAWAL_PENALTY));
            // When unwinding a strategy, a slippage on integrations will result in receiving less tokens
            // than desired so we have have to account for this with a 5% slippage.
            IStrategy(_unwindStrategy).unwindStrategy(outflow.add(outflow.preciseMul(5e16)));
        }

        _require(outflow >= _minReserveReceiveQuantity, Errors.RECEIVE_MIN_AMOUNT);

        _require(_canWithdrawReserveAmount(msg.sender, outflow), Errors.MIN_LIQUIDITY);

        _reenableReserveForStrategies();

        _burn(msg.sender, _gardenTokenQuantity);
        _safeSendReserveAsset(msg.sender, outflow);
        _updateContributorWithdrawalInfo(outflow);

        // Required withdrawable quantity is greater than existing collateral
        _require(principal >= outflow, Errors.BALANCE_TOO_LOW);
        principal = principal.sub(outflow);

        emit GardenWithdrawal(msg.sender, _to, outflow, _gardenTokenQuantity, block.timestamp);
    }

    /**
     * User can claim the rewards from the strategies that his principal
     * was invested in.
     */
    function claimReturns(address[] calldata _finalizedStrategies) external override nonReentrant {
        _onlyContributor();
        Contributor storage contributor = contributors[msg.sender];
        _require(block.timestamp > contributor.claimedAt, Errors.ALREADY_CLAIMED); // race condition check
        uint256[] memory rewards = new uint256[](7);

        rewards = rewardsDistributor.getRewards(address(this), msg.sender, _finalizedStrategies);
        _require(rewards[5] > 0 || rewards[6] > 0, Errors.NO_REWARDS_TO_CLAIM);

        if (rewards[6] > 0) {
            contributor.claimedRewards = contributor.claimedRewards.add(rewards[6]); // Rewards claimed properly
            reserveAssetRewardsSetAside = reserveAssetRewardsSetAside.sub(rewards[6]);
            contributor.claimedAt = block.timestamp; // Checkpoint of this claim
            _safeSendReserveAsset(msg.sender, rewards[6]);
            emit RewardsForContributor(msg.sender, rewards[6]);
        }
        if (rewards[5] > 0) {
            contributor.claimedBABL = contributor.claimedBABL.add(rewards[5]); // BABL Rewards claimed properly
            contributor.claimedAt = block.timestamp; // Checkpoint of this claim
            // Send BABL rewards
            rewardsDistributor.sendTokensToContributor(msg.sender, rewards[5]);
            emit BABLRewardsForContributor(msg.sender, rewards[5]);
        }
    }

    /**
     * When an strategy finishes execution, we want to make that eth available for withdrawals
     * from members of the garden.
     *
     * @param _amount                        Amount of Reserve Asset to set aside until the window ends
     * @param _rewards                       Amount of Reserve Asset to set aside forever
     * @param _returns                       Profits or losses that the strategy received
     */
    function startWithdrawalWindow(
        uint256 _amount,
        uint256 _rewards,
        int256 _returns,
        address _strategy
    ) external override {
        _onlyUnpaused();
        _require(
            (strategyMapping[msg.sender] && address(IStrategy(msg.sender).garden()) == address(this)),
            Errors.ONLY_STRATEGY
        );
        // Updates reserve asset
        if (withdrawalsOpenUntil > block.timestamp) {
            withdrawalsOpenUntil = block.timestamp.add(
                withdrawalWindowAfterStrategyCompletes.sub(withdrawalsOpenUntil.sub(block.timestamp))
            );
        } else {
            withdrawalsOpenUntil = block.timestamp.add(withdrawalWindowAfterStrategyCompletes);
        }
        reserveAssetRewardsSetAside = reserveAssetRewardsSetAside.add(_rewards);
        reserveAssetPrincipalWindow = reserveAssetPrincipalWindow.add(_amount);
        // Mark strategy as finalized
        absoluteReturns = absoluteReturns.add(_returns);
        strategies = strategies.remove(_strategy);
        finalizedStrategies.push(_strategy);
        strategyMapping[_strategy] = false;
    }

    /**
     * Pays gas costs back to the keeper from executing transactions including the past debt
     * @param _keeper             Keeper that executed the transaction
     * @param _fee                The fee paid to keeper to compensate the gas cost
     */
    function payKeeper(address payable _keeper, uint256 _fee) external override {
        _require(IBabController(controller).isValidKeeper(_keeper), Errors.ONLY_KEEPER);
        _onlyStrategy();
        keeperDebt = keeperDebt.add(_fee);
        // Pay Keeper in Reserve Asset
        if (keeperDebt > 0 && _liquidReserve() >= keeperDebt) {
            IERC20(reserveAsset).safeTransfer(_keeper, keeperDebt);
            keeperDebt = 0;
        }
    }

    /**
     * Makes a previously private garden public
     */
    function makeGardenPublic() external override {
        _require(msg.sender == creator, Errors.ONLY_CREATOR);
        _require(guestListEnabled && IBabController(controller).allowPublicGardens(), Errors.GARDEN_ALREADY_PUBLIC);
        guestListEnabled = false;
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Garden is active, deposits are enabled.
     */
    function setActive(bool _newValue) external override {
        _require(msg.sender == controller, Errors.ONLY_CONTROLLER);
        _require(active != _newValue, Errors.ONLY_INACTIVE);
        active = _newValue;
    }

    /* ============ Strategy Functions ============ */
    /**
     * Creates a new strategy calling the factory and adds it to the array
     * @param _name                          Name of the strategy
     * @param _symbol                        Symbol of the strategy
     * @param _stratParams                   Num params for the strategy
     * @param _opTypes                      Type for every operation in the strategy
     * @param _opIntegrations               Integration to use for every operation
     * @param _opEncodedDatas               Param for every operation in the strategy
     */
    function addStrategy(
        string memory _name,
        string memory _symbol,
        uint256[] calldata _stratParams,
        uint8[] calldata _opTypes,
        address[] calldata _opIntegrations,
        bytes calldata _opEncodedDatas
    ) external override {
        _onlyActive();
        _onlyContributor();

        _require(
            IIshtarGate(IBabController(controller).ishtarGate()).canAddStrategiesInAGarden(address(this), msg.sender),
            Errors.USER_CANNOT_ADD_STRATEGIES
        );
        _require(strategies.length < MAX_TOTAL_STRATEGIES, Errors.VALUE_TOO_HIGH);
        _require(_stratParams.length == 4, Errors.STRAT_PARAMS_LENGTH);
        address strategy =
            IStrategyFactory(IBabController(controller).strategyFactory()).createStrategy(
                _name,
                _symbol,
                msg.sender,
                address(this),
                _stratParams
            );
        strategyMapping[strategy] = true;
        totalStake = totalStake.add(_stratParams[1]);
        strategies.push(strategy);
        IStrategy(strategy).setData(_opTypes, _opIntegrations, _opEncodedDatas);
        isGardenStrategy[strategy] = true;
        emit AddStrategy(strategy, _name, _stratParams[3]);
    }

    /**
     * Allocates garden capital to an strategy
     *
     * @param _capital        Amount of capital to allocate to the strategy
     */
    function allocateCapitalToStrategy(uint256 _capital) external override {
        _onlyStrategy();
        _onlyActive();
        _reenableReserveForStrategies();

        uint256 protocolMgmtFee = IBabController(controller).protocolManagementFee().preciseMul(_capital);
        _require(_capital.add(protocolMgmtFee) <= _liquidReserve(), Errors.MIN_LIQUIDITY);

        // Take protocol mgmt fee
        _payProtocolFeeFromGarden(reserveAsset, protocolMgmtFee);

        // Send Capital to strategy
        IERC20(reserveAsset).safeTransfer(msg.sender, _capital);
    }

    /*
     * Remove an expire candidate from the strategy Array
     * @param _strategy      Strategy to remove
     */
    function expireCandidateStrategy(address _strategy) external override {
        _onlyStrategy();
        strategies = strategies.remove(_strategy);
        strategyMapping[_strategy] = false;
    }

    /*
     * Burns the stake of the strategist of a given strategy
     * @param _strategy      Strategy
     */
    function burnStrategistStake(address _strategist, uint256 _amount) external override {
        _onlyStrategy();
        if (_amount >= balanceOf(_strategist)) {
            // Avoid underflow condition
            _amount = balanceOf(_strategist);
        }
        _burn(_strategist, _amount);
    }

    /* ============ External Getter Functions ============ */

    /**
     * Gets current strategies
     *
     * @return  address[]        Returns list of addresses
     */

    function getStrategies() external view override returns (address[] memory) {
        return strategies;
    }

    /**
     * Gets finalized strategies
     *
     * @return  address[]        Returns list of addresses
     */

    function getFinalizedStrategies() external view override returns (address[] memory) {
        return finalizedStrategies;
    }

    function getContributor(address _contributor)
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        Contributor storage contributor = contributors[_contributor];
        uint256 contributorPower =
            rewardsDistributor.getContributorPower(
                address(this),
                _contributor,
                contributor.initialDepositAt,
                block.timestamp
            );
        uint256 balance = balanceOf(_contributor);
        uint256 lockedBalance = getLockedBalance(_contributor);
        return (
            contributor.lastDepositAt,
            contributor.initialDepositAt,
            contributor.claimedAt,
            contributor.claimedBABL,
            contributor.claimedRewards,
            contributor.totalDeposits > contributor.withdrawnSince
                ? contributor.totalDeposits.sub(contributor.withdrawnSince)
                : 0,
            balance,
            lockedBalance,
            contributorPower
        );
    }

    /**
     * Get the expected reserve asset to be withdrawaled
     *
     * @param _gardenTokenQuantity             Quantity of Garden tokens to withdrawal
     *
     * @return  uint256                     Expected reserve asset quantity withdrawaled
     */
    function getExpectedReserveWithdrawalQuantity(uint256 _gardenTokenQuantity)
        external
        view
        override
        returns (uint256)
    {
        return _getWithdrawalReserveQuantity(reserveAsset, _gardenTokenQuantity);
    }

    /**
     * Checks balance locked for strategists in active strategies
     *
     * @param _contributor                 Address of the account
     *
     * @return  uint256                    Returns the amount of locked garden tokens for the account
     */
    function getLockedBalance(address _contributor) public view override returns (uint256) {
        uint256 lockedAmount;
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            if (_contributor == strategy.strategist()) {
                lockedAmount = lockedAmount.add(strategy.stake());
            }
        }
        // Avoid overflows if off-chain voting system fails
        if (balanceOf(_contributor) < lockedAmount) lockedAmount = balanceOf(_contributor);
        return lockedAmount;
    }

    function getGardenTokenMintQuantity(
        uint256 _reserveAssetQuantity,
        bool isDeposit // Value of reserve asset net of fees
    ) public view override returns (uint256) {
        // Get valuation of the Garden with the quote asset as the reserve asset.
        // Reverts if price is not found
        uint256 baseUnits = uint256(10)**ERC20Upgradeable(reserveAsset).decimals();
        uint256 normalizedReserveQuantity = _reserveAssetQuantity.preciseDiv(baseUnits);
        // First deposit
        if (totalSupply() == 0) {
            return normalizedReserveQuantity;
        }
        uint256 gardenValuationPerToken =
            IGardenValuer(IBabController(controller).gardenValuer()).calculateGardenValuation(
                address(this),
                reserveAsset
            );
        if (isDeposit) {
            gardenValuationPerToken = gardenValuationPerToken.sub(normalizedReserveQuantity.preciseDiv(totalSupply()));
        }
        return normalizedReserveQuantity.preciseDiv(gardenValuationPerToken);
    }

    /* ============ Internal Functions ============ */
    /**
     * Gets liquid reserve available for to Garden.
     */
    function _liquidReserve() private view returns (uint256) {
        return
            IERC20(reserveAsset).balanceOf(address(this)).sub(reserveAssetPrincipalWindow).sub(
                reserveAssetRewardsSetAside
            );
    }

    /**
     * When the window of withdrawals finishes, we need to make the capital available again for investments
     * We still keep the profits aside.
     */
    function _reenableReserveForStrategies() private {
        if (block.timestamp >= withdrawalsOpenUntil) {
            withdrawalsOpenUntil = 0;
            reserveAssetPrincipalWindow = 0;
        }
    }

    /**
     * Check if the fund has reserve amount available for withdrawals.
     * If it returns false, reserve pool would be available.
     * @param _contributor                   Address of the contributors
     * @param _amount                        Amount of ETH to withdraw
     */
    function _canWithdrawReserveAmount(address _contributor, uint256 _amount) private view returns (bool) {
        // Reserve rewards cannot be withdrawn. Only claimed
        uint256 liquidReserve = IERC20(reserveAsset).balanceOf(address(this)).sub(reserveAssetRewardsSetAside);

        // Withdrawal open
        if (block.timestamp <= withdrawalsOpenUntil) {
            // There is a window but there is more than needed
            if (liquidReserve.sub(reserveAssetPrincipalWindow) > _amount) {
                return true;
            }
            // Pro rata withdrawals
            uint256 contributorPower =
                rewardsDistributor.getContributorPower(
                    address(this),
                    _contributor,
                    contributors[_contributor].initialDepositAt,
                    block.timestamp
                );
            return
                reserveAssetPrincipalWindow.preciseMul(contributorPower).add(
                    liquidReserve.sub(reserveAssetPrincipalWindow)
                ) >= _amount;
        }
        return liquidReserve.sub(reserveAssetPrincipalWindow) >= _amount;
    }

    /**
     * Gets the total active capital currently invested in strategies
     *
     * @return uint256       Total amount active
     * @return uint256       Total amount active in the largest strategy
     * @return address       Address of the largest strategy
     */
    function _getActiveCapital()
        private
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        uint256 totalActiveCapital;
        uint256 maxAllocation;
        address maxStrategy = address(0);
        for (uint8 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            if (strategy.isStrategyActive()) {
                uint256 allocation = strategy.capitalAllocated();
                totalActiveCapital = totalActiveCapital.add(allocation);
                if (allocation > maxAllocation) {
                    maxAllocation = allocation;
                    maxStrategy = strategies[i];
                }
            }
        }
        return (totalActiveCapital, maxAllocation, maxStrategy);
    }

    /**
     * Pays the _feeQuantity from the _garden denominated in _token to the protocol fee recipient
     * @param _token                   Address of the token to pay with
     * @param _feeQuantity             Fee to transfer
     */
    function _payProtocolFeeFromGarden(address _token, uint256 _feeQuantity) private {
        IERC20(_token).safeTransfer(IBabController(controller).treasury(), _feeQuantity);
    }

    // Disable garden token transfers. Allow minting and burning.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 _amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, _amount);
        _require(
            from == address(0) ||
                to == address(0) ||
                (IBabController(controller).gardenTokensTransfersEnabled() && !guestListEnabled),
            Errors.GARDEN_TRANSFERS_DISABLED
        );
    }

    function _safeSendReserveAsset(address payable _to, uint256 _amount) private {
        if (reserveAsset == WETH) {
            // Check that the withdrawal is possible
            // Unwrap WETH if ETH balance lower than netFlowQuantity
            if (address(this).balance < _amount) {
                IWETH(WETH).withdraw(_amount.sub(address(this).balance));
            }
            // Send ETH
            Address.sendValue(_to, _amount);
        } else {
            // Send reserve asset
            IERC20(reserveAsset).safeTransfer(_to, _amount);
        }
    }

    function _getWithdrawalReserveQuantity(address _reserveAsset, uint256 _gardenTokenQuantity)
        private
        view
        returns (uint256)
    {
        // Get valuation of the Garden with the quote asset as the reserve asset. Returns value in precise units (10e18)
        // Reverts if price is not found
        uint256 gardenValuationPerToken =
            IGardenValuer(IBabController(controller).gardenValuer()).calculateGardenValuation(
                address(this),
                _reserveAsset
            );

        uint256 totalWithdrawalValueInPreciseUnits = _gardenTokenQuantity.preciseMul(gardenValuationPerToken);
        return totalWithdrawalValueInPreciseUnits.preciseMul(10**ERC20Upgradeable(_reserveAsset).decimals());
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorDepositInfo(
        address _contributor,
        uint256 previousBalance,
        uint256 _reserveAssetQuantity
    ) private {
        Contributor storage contributor = contributors[_contributor];
        // If new contributor, create one, increment count, and set the current TS
        if (previousBalance == 0 || contributor.initialDepositAt == 0) {
            _require(totalContributors < maxContributors, Errors.MAX_CONTRIBUTORS);
            totalContributors = totalContributors.add(1);
            contributor.initialDepositAt = block.timestamp;
        }
        // We make checkpoints around contributor deposits to avoid fast loans and give the right rewards afterwards
        contributor.totalDeposits = contributor.totalDeposits.add(_reserveAssetQuantity);
        contributor.lastDepositAt = block.timestamp;
        rewardsDistributor.updateGardenPowerAndContributor(address(this), _contributor, previousBalance, true, pid);
        pid++;
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorWithdrawalInfo(uint256 _netflowQuantity) private {
        Contributor storage contributor = contributors[msg.sender];
        // If sold everything
        if (balanceOf(msg.sender) == 0) {
            contributor.lastDepositAt = 0;
            contributor.initialDepositAt = 0;
            contributor.withdrawnSince = 0;
            contributor.totalDeposits = 0;
            totalContributors = totalContributors.sub(1);
        } else {
            contributor.withdrawnSince = contributor.withdrawnSince.add(_netflowQuantity);
        }
        rewardsDistributor.updateGardenPowerAndContributor(address(this), msg.sender, 0, false, pid);
        pid++;
    }

    // solhint-disable-next-line
    receive() external payable {}
}

contract GardenV3 is Garden {}
