const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { impersonateAddress } = require("../../utils/rpc");
const addresses = require("../../utils/addresses");
const { deployFolioFixture } = require("../fixtures/ControllerFixture");

const { loadFixture } = waffle;

describe("CompoundIntegration", function() {
  let system;
  let owner;
  let controller;
  let compoundBorrowing;
  const daiWhaleAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  let fund;
  let compAbi;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    owner = system.owner;
    controller = system.folioController;
    compoundBorrowing = system.integrations.compoundIntegration;
    compAbi = compoundBorrowing.interface;
    fund = system.funds.one;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await controller.deployed();
      const deployedC = await compoundBorrowing.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedC).to.equal(true);
    });
  });

  describe("CompoundBorrowing", async function() {
    let whaleSigner;
    let cethToken;
    let daiToken;
    let cdaiToken;
    let whaleWeth;
    let wethToken;
    let comptroller;
    let usdcToken;
    let cusdcToken;

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(daiWhaleAddress);
      wethToken = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
      whaleWeth = await impersonateAddress(addresses.holders.WETH);
      comptroller = await ethers.getContractAt(
        "IComptroller",
        addresses.compound.Comptroller
      );
      daiToken = await ethers.getContractAt("IERC20", addresses.tokens.DAI);
      cdaiToken = await ethers.getContractAt("ICToken", addresses.tokens.CDAI);
      usdcToken = await ethers.getContractAt("IERC20", addresses.tokens.USDC);
      cusdcToken = await ethers.getContractAt(
        "ICToken",
        addresses.tokens.CUSDC
      );
      cethToken = await ethers.getContractAt("ICEther", addresses.tokens.CETH);
    });

    describe("Compound Borrowing/Lending", function() {
      it("can supply ether", async function() {
        expect(await cethToken.balanceOf(fund.address)).to.equal(0);
        await expect(() =>
          owner.sendTransaction({
            to: fund.address,
            gasPrice: 0,
            value: ethers.utils.parseEther("10")
          })
        ).to.changeEtherBalance(owner, ethers.utils.parseEther("-10"));
        // const data = compAbi.encodeFunctionData(
        //   compoundBorrowing.interface.functions[
        //     "depositCollateral(address,uint256)"
        //   ],
        //   [addresses.tokens.WETH, ethers.utils.parseEther("1")]
        // );
        // await fund.callIntegration(
        //   compoundBorrowing.address,
        //   ethers.utils.parseEther("1"),
        //   data,
        //   {
        //     gasPrice: 0
        //   }
        // );
        await fund.depositCollateral(
          "compound",
          addresses.tokens.WETH,
          ethers.utils.parseEther("10"),
          {
            gasPrice: 0
          }
        );
        expect(await cethToken.balanceOf(compoundBorrowing.address)).to.equal(
          0
        );
        const balance = await cethToken.balanceOf(fund.address);
        expect(balance).to.be.gt(0);
      });

      it("can supply erc20", async function() {
        expect(
          await daiToken
            .connect(whaleSigner)
            .transfer(fund.address, ethers.utils.parseEther("1000"), {
              gasPrice: 0
            })
        );
        expect(await cdaiToken.balanceOf(fund.address)).to.equal(0);
        expect(await daiToken.balanceOf(fund.address)).to.equal(
          ethers.utils.parseEther("1000")
        );

        await fund.depositCollateral(
          "compound",
          addresses.tokens.DAI,
          ethers.utils.parseEther("100"),
          {
            gasPrice: 0
          }
        );

        const balance = await cdaiToken.balanceOf(fund.address);
        expect(balance).to.be.gt(0);
      });

      it("can supply ether and borrow dai", async function() {
        // TODO
      });

      // it("can supply dai and borrow usdc", async function() {
      // });

      // it("can supply ether, borrow dai and repay", async function() {
      //
    });
  });
});
