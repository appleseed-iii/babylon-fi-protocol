const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("FundValuer", function() {
  let controller;
  let valuer;
  let fund;
  let weth;

  beforeEach(async () => {
    const { folioController, fundValuer, funds } = await loadFixture(
      deployFolioFixture
    );
    fund = funds.one;
    controller = folioController;
    valuer = fundValuer;
    weth = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployedc = await controller.deployed();
      const deployed = await valuer.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe("Calls FundValuer", function() {
    it("should return 0.1 for fund1", async function() {
      const wethInFund = await weth.balanceOf(fund.address);
      // const priceOfWeth = await fund.getPrice(
      //   addresses.tokens.WETH,
      //   addresses.tokens.DAI
      // );
      console.log("wethInFund", wethInFund);
      // console.log('format', ethers.utils.formatEther(100000000000000000));
      const pricePerFundToken = await valuer.calculateFundValuation(
        fund.address,
        addresses.tokens.WETH
      );
      const tokens = await fund.totalSupply();
      expect(pricePerFundToken.mul(tokens / 1000).div(10 ** 15)).to.equal(
        ethers.utils.parseEther("0.1")
      );
    });
  });
});
