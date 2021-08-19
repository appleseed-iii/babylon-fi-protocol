module.exports = async ({ getTenderlyContract, getNamedAccounts, deployments, getRapid, network, tenderly }) => {
  const { deployer } = await getNamedAccounts();
  const gasPrice = await getRapid();
  const { deploy } = deployments;
  const signer = await getSigner(deployer);

  const bablToken = await deployments.get('BABLToken');
  const timelockController = await deployments.get('TimelockController');

  const timelockControllerContract = await ethers.getContractAt('TimelockController', timelockController.address, signer);

  const PROPOSER_ROLE = await timelockControllerContract.PROPOSER_ROLE();
  const EXECUTOR_ROLE = await timelockControllerContract.EXECUTOR_ROLE();

  const governor = await deploy('BabylonGovernor', {
    from: deployer,
    args: [bablToken.address, timelockController.address],
    log: true,
    gasPrice,
  });

  console.log('Deployed Governor Babylon at', governor.address);

  if (network.live && governor.newlyDeployed) {
    const contract = await getTenderlyContract('BabylonGovernor');
    await tenderly.push(contract);

    // We give proposer and executor permissions to Governor
    console.log('Setting Governor on TimelockController');
    await (
      await timelockControllerContract.grantRole(PROPOSER_ROLE, governor.address, { gasPrice })
    ).wait();
    await (
      await timelockControllerContract.grantRole(EXECUTOR_ROLE, governor.address, { gasPrice })
    ).wait();

    // TODO Deployer renounce TIMELOCK_ADMIN_ROLE
    //  await (await timelockControllerContract.connect(deployer).renounceRole(TIMELOCK_ADMIN_ROLE, deployer.address, { gasPrice })).wait();
  }
};

module.exports.tags = ['BabylonGovernor'];
