const addresses = require('../../lib/addresses');

module.exports = async ({ getNamedAccounts, deployments, ethers, getRapid }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const controller = await deployments.get('BabControllerProxy');

  await deploy('SushiswapPoolIntegration', {
    from: deployer,
    args: [controller.address, addresses.tokens.WETH, addresses.sushiswap.router],
    log: true,
    gasPrice,
  });
};

module.exports.tags = ['Sushiswap'];
module.exports.dependencies = ['Uniswap'];
