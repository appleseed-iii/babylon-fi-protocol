const { expect } = require('chai');
const chaiAsPromised = require('chai-as-promised');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;
require('chai').use(chaiAsPromised);

const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
  deposit,
  DEFAULT_STRATEGY_PARAMS,
} = require('../fixtures/StrategyHelper.js');
const { increaseTime } = require('../utils/test-helpers');

const addresses = require('../../utils/addresses');
const { ONE_DAY_IN_SECONDS, ONE_ETH } = require('../../utils/constants.js');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');

describe('Strategy', function () {
  let strategyDataset;
  let strategyCandidate;
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let garden2;
  let strategy11;
  let strategy21;
  let wethToken;
  let daiWethPair;
  let aaveLendIntegration;
  let kyberTradeIntegration;
  let uniswapPoolIntegration;
  let balancerIntegration;
  let oneInchPoolIntegration;
  let yearnVaultIntegration;

  beforeEach(async () => {
    ({
      owner,
      signer1,
      garden1,
      garden2,
      strategy11,
      strategy21,
      signer2,
      signer3,
      aaveLendIntegration,
      kyberTradeIntegration,
      uniswapPoolIntegration,
      balancerIntegration,
      oneInchPoolIntegration,
      yearnVaultIntegration,
    } = await loadFixture(deployFolioFixture));

    strategyDataset = await ethers.getContractAt('Strategy', strategy11);
    strategyCandidate = await ethers.getContractAt('Strategy', strategy21);

    wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    daiWethPair = await ethers.getContractAt('IUniswapV2PairB', addresses.uniswap.pairs.wethdai);
  });

  describe('Strategy Deployment', async function () {
    it('should deploy contract successfully', async function () {
      const deployed = await strategyDataset.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('changeStrategyDuration', function () {
    it('strategist should be able to change the duration of an strategy strategy', async function () {
      await expect(strategyDataset.connect(signer1).changeStrategyDuration(ONE_DAY_IN_SECONDS)).to.not.be.reverted;
    });

    it('other member should be able to change the duration of an strategy', async function () {
      await expect(strategyDataset.connect(signer3).changeStrategyDuration(ONE_DAY_IN_SECONDS)).to.be.reverted;
    });
  });

  describe('getStrategyDetails', async function () {
    it('should return the expected strategy properties', async function () {
      const [
        address,
        strategist,
        integration,
        stake,
        absoluteTotalVotes,
        totalVotes,
        capitalAllocated,
        capitalReturned,
        duration,
        expectedReturn,
        maxCapitalRequested,
        minRebalanceCapital,
        enteredAt,
      ] = await strategyDataset.getStrategyDetails();

      expect(address).to.equal(strategyDataset.address);
      expect(strategist).to.equal(signer1.address);
      expect(integration).to.not.equal(addresses.zero);
      expect(stake).to.equal(ethers.utils.parseEther('1'));
      expect(absoluteTotalVotes).to.equal(ethers.utils.parseEther('1'));
      expect(totalVotes).to.equal(ethers.utils.parseEther('1'));
      expect(capitalAllocated).to.equal(ethers.BigNumber.from(0));
      expect(capitalReturned).to.equal(ethers.BigNumber.from(0));
      expect(duration).to.equal(ethers.BigNumber.from(ONE_DAY_IN_SECONDS * 30));
      expect(expectedReturn).to.equal(ethers.utils.parseEther('0.05'));
      expect(maxCapitalRequested).to.equal(ethers.utils.parseEther('10'));
      expect(minRebalanceCapital).to.equal(ethers.utils.parseEther('1'));
      expect(enteredAt.isZero()).to.equal(false);
    });
  });

  describe('getStrategyState', async function () {
    it('should return the expected strategy state', async function () {
      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyDataset.getStrategyState();

      expect(address).to.equal(strategyDataset.address);
      expect(active).to.equal(false);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.equal(ethers.BigNumber.from(0));
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));
    });
  });

  describe('resolveVoting', async function () {
    it('should push results of the voting on-chain', async function () {
      const signer1Balance = await garden2.balanceOf(signer1.getAddress());
      const signer2Balance = await garden2.balanceOf(signer2.getAddress());

      await strategyCandidate.resolveVoting(
        [signer1.getAddress(), signer2.getAddress()],
        [signer1Balance, signer2Balance],
        signer1Balance.add(signer2Balance).toString(),
        signer1Balance.add(signer2Balance).toString(),
        42,
        {
          gasPrice: 0,
        },
      );

      expect(await strategyCandidate.getUserVotes(signer1.getAddress())).to.equal(signer1Balance);
      expect(await strategyCandidate.getUserVotes(signer2.getAddress())).to.equal(signer2Balance);

      const [, , , , absoluteTotalVotes, totalVotes] = await strategyCandidate.getStrategyDetails();

      expect(absoluteTotalVotes).to.equal(ethers.utils.parseEther('5.1'));
      expect(totalVotes).to.equal(ethers.utils.parseEther('5.1'));

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyCandidate.getStrategyState();

      expect(address).to.equal(strategyCandidate.address);
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.equal(ethers.BigNumber.from(0));
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);
    });

    it("can't vote if voting window is closed", async function () {
      const signer1Balance = await garden2.balanceOf(signer1.getAddress());
      const signer2Balance = await garden2.balanceOf(signer2.getAddress());

      increaseTime(ONE_DAY_IN_SECONDS * 7);

      await expect(
        strategyCandidate.resolveVoting(
          [signer1.getAddress(), signer2.getAddress()],
          [signer1Balance, signer2Balance],
          signer1Balance.add(signer2Balance).toString(),
          signer1Balance.add(signer2Balance).toString(),
          42,
          {
            gasPrice: 0,
          },
        ),
      ).to.be.revertedWith(/voting window is closed/i);
    });

    it("can't push voting results twice", async function () {
      const signer1Balance = await garden2.balanceOf(signer1.getAddress());
      const signer2Balance = await garden2.balanceOf(signer2.getAddress());

      await strategyCandidate.resolveVoting(
        [signer1.getAddress(), signer2.getAddress()],
        [signer1Balance, signer2Balance],
        signer1Balance.add(signer2Balance).toString(),
        signer1Balance.add(signer2Balance).toString(),
        42,
        {
          gasPrice: 0,
        },
      );

      await expect(
        strategyCandidate.resolveVoting(
          [signer1.getAddress(), signer2.getAddress()],
          [signer1Balance, signer2Balance],
          signer1Balance.add(signer2Balance).toString(),
          signer1Balance.add(signer2Balance).toString(),
          42,
          {
            gasPrice: 0,
          },
        ),
      ).to.be.revertedWith(/voting is already resolved/i);
    });
  });

  describe('executeStrategy', async function () {
    it('should execute strategy', async function () {
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('2'), 42);

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();

      expect(address).to.equal(strategyContract.address);
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);
    });

    it('should not be able to unwind an active strategy with not enough capital', async function () {
      const strategyContract = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      await expect(strategyContract.unwindStrategy(ethers.utils.parseEther('1'))).to.be.reverted;
    });

    it('should be able to unwind an active strategy with enough capital', async function () {
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      expect(await wethToken.balanceOf(garden1.address)).to.be.gt(ethers.utils.parseEther('2'));
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('2'), 0);
      expect(await wethToken.balanceOf(garden1.address)).to.be.lt(ethers.utils.parseEther('0.1'));
      expect(await strategyContract.capitalAllocated()).to.equal(ethers.utils.parseEther('2'));
      await strategyContract.unwindStrategy(ethers.utils.parseEther('1'));
      expect(await strategyContract.capitalAllocated()).to.equal(ethers.utils.parseEther('1'));
      expect(await wethToken.balanceOf(garden1.address)).to.be.gt(ethers.utils.parseEther('1'));
    });

    it('should not be able to unwind an active strategy with enough capital if it is not the owner', async function () {
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      expect(await wethToken.balanceOf(garden1.address)).to.be.gt(ethers.utils.parseEther('2'));
      await executeStrategy(garden1, strategyContract, ethers.utils.parseEther('2'), 0);
      expect(await wethToken.balanceOf(garden1.address)).to.be.lt(ethers.utils.parseEther('0.1'));
      expect(await strategyContract.capitalAllocated()).to.equal(ethers.utils.parseEther('2'));
      await expect(strategyContract.connect(signer3).unwindStrategy(ethers.utils.parseEther('1'))).to.be.reverted;
    });

    it('can execute strategy twice', async function () {
      const strategyContract = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      deposit(garden1, [signer1, signer2]);

      await executeStrategy(garden1, strategyContract);

      const [, , , , executedAt] = await strategyContract.getStrategyState();

      await executeStrategy(garden1, strategyContract);

      const [, , , , newExecutedAt] = await strategyContract.getStrategyState();

      // doesn't update executedAt
      expect(executedAt).to.be.equal(newExecutedAt);
    });

    it('refuse to pay a high fee to the keeper', async function () {
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      await expect(
        strategyContract.executeStrategy(ethers.utils.parseEther('1'), ethers.utils.parseEther('100'), {
          gasPrice: 0,
        }),
      ).to.be.revertedWith(/fee is too high/i);
    });
  });

  describe('getNAV', async function () {
    it('should get the NAV value of a long strategy', async function () {
      const strategyContract = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );
      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(nav).to.be.closeTo(ONE_ETH, ONE_ETH.div(500));
    });

    it('should get the NAV value of a Yearn Farming strategy', async function () {
      const strategyContract = await createStrategy(
        2,
        'active',
        [signer1, signer2, signer3],
        yearnVaultIntegration.address,
        garden1,
      );
      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(nav).to.be.closeTo(ONE_ETH, ONE_ETH.div(500));
    });

    it('should get the NAV value of a lend strategy', async function () {
      const strategyContract = await createStrategy(
        3,
        'active',
        [signer1, signer2, signer3],
        aaveLendIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [addresses.tokens.DAI],
      );
      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(nav).to.be.closeTo(ONE_ETH, ONE_ETH.div(500));
    });

    it('should get the NAV value of a BalancerPool strategy', async function () {
      const strategyContract = await createStrategy(
        1,
        'active',
        [signer1, signer2, signer3],
        balancerIntegration.address,
        garden1,
      );

      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      // So much slipage at Balancer 😭
      expect(nav).to.be.closeTo(ONE_ETH, ONE_ETH.div(50));
    });

    it('should get the NAV value of a OneInchPool strategy', async function () {
      const daiWethOneInchPair = await ethers.getContractAt('IMooniswap', addresses.oneinch.pools.wethdai);
      const strategyContract = await createStrategy(
        1,
        'active',
        [signer1, signer2, signer3],
        oneInchPoolIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [daiWethOneInchPair.address],
      );

      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(nav).to.be.closeTo(ONE_ETH, ONE_ETH.div(100));
    });

    it('should get the NAV value of a UniswapPool strategy', async function () {
      const strategyContract = await createStrategy(
        1,
        'active',
        [signer1, signer2, signer3],
        uniswapPoolIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [daiWethPair.address],
      );
      const nav = await strategyContract.getNAV();
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(nav).to.be.closeTo(ONE_ETH, ONE_ETH.div(400));
    });
  });

  describe('finalizeStrategy', async function () {
    it('should finalize strategy with negative profits', async function () {
      const strategyContract = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      await finalizeStrategy(garden1, strategyContract, 42);
      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();

      expect(address).to.equal(strategyContract.address);
      expect(active).to.equal(false);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(true);
      expect(executedAt).to.not.equal(0);
      expect(exitedAt).to.not.equal(0);

      // Keeper gets paid
      expect(await wethToken.balanceOf(await owner.getAddress())).to.equal(42);

      const capitalAllocated = await strategyContract.capitalAllocated();
      const capitalReturned = await strategyContract.capitalReturned();
      expect(capitalReturned).to.be.lt(capitalAllocated);
    });

    it('should finalize strategy with profits', async function () {
      const strategyContract = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      await injectFakeProfits(strategyContract, ethers.utils.parseEther('1000'));
      await finalizeStrategy(garden1, strategyContract, 42);
      const capitalAllocated = await strategyContract.capitalAllocated();
      const capitalReturned = await strategyContract.capitalReturned();

      expect(capitalReturned).to.be.gt(capitalAllocated);
    });

    it("can't finalize strategy twice", async function () {
      const strategyContract = await createStrategy(
        0,
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration.address,
        garden1,
      );

      await finalizeStrategy(garden1, strategyContract, 42);

      await expect(strategyContract.finalizeStrategy(42, { gasPrice: 0 })).to.be.reverted;
    });
  });
});
