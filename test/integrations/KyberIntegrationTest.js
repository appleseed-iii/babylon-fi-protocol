const { expect } = require('chai');
const { waffle, ethers } = require('hardhat');
// const { impersonateAddress } = require("../../utils/rpc");
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const addresses = require('../../utils/addresses');
const { ONE_DAY_IN_SECONDS } = require('../../utils/constants');

const { loadFixture } = waffle;

describe('KyberTradeIntegration', function () {
  let babController;
  let kyberTradeIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let strategy11;
  let strategyContract;

  beforeEach(async () => {
    ({ babController, garden1, strategy11, kyberTradeIntegration, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
    strategyContract = await ethers.getContractAt('Strategy', strategy11);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedKyber = await kyberTradeIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedKyber).to.equal(true);
    });
  });

  describe('Trading', function () {
    let wethToken;
    let usdcToken;

    beforeEach(async () => {
      wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
      usdcToken = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
    });

    it('trade weth to usdc', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('2'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('2'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('2'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('2'),
      });
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('2'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('2'),
      });
      expect(await wethToken.balanceOf(garden1.address)).to.equal(ethers.utils.parseEther('6.1'));

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      const user2GardenBalance = await garden1.balanceOf(signer2.getAddress());
      const user3GardenBalance = await garden1.balanceOf(signer3.getAddress());

      await strategyContract.resolveVoting(
        [signer2.getAddress(), signer3.getAddress()],
        [user2GardenBalance, user3GardenBalance],
        user2GardenBalance.add(user3GardenBalance).toString(),
        user2GardenBalance.add(user3GardenBalance).toString(),
        0,
        {
          gasPrice: 0,
        },
      );

      await strategyContract.executeInvestment(ethers.utils.parseEther('1'), 0, {
        gasPrice: 0,
      });

      expect(await wethToken.balanceOf(strategyContract.address)).to.equal(ethers.utils.parseEther('0'));
      expect(await usdcToken.balanceOf(strategyContract.address)).to.be.gt(ethers.utils.parseEther('97') / 10 ** 12);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);

      await strategyContract.finalizeInvestment(0, { gasPrice: 0 });
      expect(await usdcToken.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
});
