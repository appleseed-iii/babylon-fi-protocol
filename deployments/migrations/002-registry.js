module.exports = async ({
  tenderly,
  getTenderlyContract,
  network,
  getNamedAccounts,
  deployments,
  ethers,
  getRapid,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();

  const bablToken = await deployments.get('BABLToken');

  const timeLockRegistry = await deploy('TimeLockRegistry', {
    from: deployer,
    args: [bablToken.address],
    log: true,
    gasPrice,
  });

  if (timeLockRegistry.newlyDeployed) {
    const bablTokenContract = await ethers.getContractAt('BABLToken', bablToken.address);
    // Sets the Time Lock Registry address
    await bablTokenContract.setTimeLockRegistry(timeLockRegistry.address);
  }

  if (network.live && timeLockRegistry.newlyDeployed) {
    const contract = await getTenderlyContract('TimeLockRegistry');
    await tenderly.push(contract);
  }
};

module.exports.tags = ['Registry'];
module.exports.dependencies = ['Controller'];
