const { expect } = require('chai');
const { ethers } = require('hardhat');
const { createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { increaseTime, getERC20 } = require('utils/test-helpers');
const { STRATEGY_EXECUTE_MAP, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');

describe('ConvexStakeIntegrationTest', function () {
  let convexStakeIntegration;
  let curvePoolIntegration;
  let signer1;
  let signer2;
  let signer3;

  // Used to create addresses info. do not remove
  async function logConvexPools() {
    const convexpools = await Promise.all(
      [...Array(40).keys()].map(async (pid) => {
        return await createConvexPoolInfo(pid);
      }),
    );
    console.log(convexpools.filter((c) => c));
  }

  async function createConvexPoolInfo(pid) {
    const crvAddressProvider = await ethers.getContractAt(
      'ICurveAddressProvider',
      '0x0000000022d53366457f9d5e68ec105046fc4383',
    );
    const convexBooster = await ethers.getContractAt('IBooster', '0xF403C135812408BFbE8713b5A23a04b3D48AAE31');
    const crvRegistry = await ethers.getContractAt('ICurveRegistry', await crvAddressProvider.get_registry());
    const poolInfo = await convexBooster.poolInfo(pid);
    const crvLpTokens = await Promise.all(
      Object.values(addresses.curve.pools.v3).map(async (address) => {
        return await crvRegistry.get_lp_token(address);
      }),
    );
    const foundIndex = crvLpTokens.findIndex((e) => e === poolInfo[0]);
    if (foundIndex > -1) {
      return {
        name: Object.keys(addresses.curve.pools.v3)[foundIndex],
        crvpool: Object.values(addresses.curve.pools.v3)[foundIndex],
        cvxpool: poolInfo[1],
      };
    }
  }

  // logConvexPools();

  beforeEach(async () => {
    ({ curvePoolIntegration, convexStakeIntegration, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('Convex Stake Multigarden multiasset', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      // { token: addresses.tokens.DAI, name: 'DAI' },
      // { token: addresses.tokens.USDC, name: 'USDC' },
      // { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(async ({ token, name }) => {
      addresses.convex.pools.forEach(({ crvpool, cvxpool, name }) => {
        it(`can enter ${name} CRV pool and stake into convex`, async function () {
          // TODO: bump the block number to fix these tests
          if (['y', 'tusd', 'busdv2'].includes(name)) {
            return;
          }
          await depositAndStakeStrategy(crvpool, cvxpool, token);
        });
      });
    });
    it(`cannot enter an invalid pool`, async function () {
      await expect(tryDepositAndStakeStrategy(ADDRESS_ZERO, ADDRESS_ZERO, addresses.tokens.WETH)).to.be.reverted;
    });
  });

  async function depositAndStakeStrategy(crvpool, cvxpool, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await getERC20(token);
    await depositFunds(token, garden);
    const crvAddressProvider = await ethers.getContractAt(
      'ICurveAddressProvider',
      '0x0000000022d53366457f9d5e68ec105046fc4383',
    );
    const crvRegistry = await ethers.getContractAt('ICurveRegistry', await crvAddressProvider.get_registry());
    const convexBooster = await ethers.getContractAt('IBooster', '0xF403C135812408BFbE8713b5A23a04b3D48AAE31');
    const crvLpToken = await getERC20(await crvRegistry.get_lp_token(crvpool));
    const pid = (await convexStakeIntegration.getPid(cvxpool))[1].toNumber();
    const poolInfo = await convexBooster.poolInfo(pid);
    const convexRewardToken = await getERC20(poolInfo[3]);

    const strategyContract = await createStrategy(
      'lpStack',
      'vote',
      [signer1, signer2, signer3],
      [curvePoolIntegration.address, convexStakeIntegration.address],
      garden,
      false,
      [crvpool, 0, cvxpool, 0],
    );
    const amount = STRATEGY_EXECUTE_MAP[token];
    const balanceBeforeExecuting = await gardenReserveAsset.balanceOf(garden.address);
    await executeStrategy(strategyContract, { amount });
    // Check NAV
    const nav = await strategyContract.getNAV();
    expect(nav).to.be.gt(amount.sub(amount.div(35)));

    expect(await crvLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await convexRewardToken.balanceOf(strategyContract.address)).to.be.gt(0);

    // Check reward after a week
    await increaseTime(ONE_DAY_IN_SECONDS * 7);
    expect(await strategyContract.getNAV()).to.be.gte(nav);
    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract, { gasLimit: 99900000 });
    expect(await crvLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await convexRewardToken.balanceOf(strategyContract.address)).to.equal(0);

    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gte(balanceBeforeExiting);
    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.closeTo(
      balanceBeforeExecuting,
      balanceBeforeExecuting.div(35),
    );
  }

  async function tryDepositAndStakeStrategy(crvpool, cvxpool, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    await depositFunds(token, garden);

    const strategyContract = await createStrategy(
      'lpStack',
      'vote',
      [signer1, signer2, signer3],
      [curvePoolIntegration.address, convexStakeIntegration.address],
      garden,
      false,
      [crvpool, 0, cvxpool, 0],
    );
    await expect(executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] })).to.be.reverted;
  }
});
