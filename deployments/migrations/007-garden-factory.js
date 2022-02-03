module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getGasPrice,
  getController,
}) => {
  const { deploy } = deployments;
  const { deployer, owner } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const { maxPriorityFeePerGas } = await getGasPrice();

  const gardenFactoryContract = 'GardenFactory';
  const gardenContract = 'Garden';
  const beaconContract = 'GardenBeacon';

  const controller = await getController();

  const garden = await deploy(gardenContract, {
    from: deployer,
    args: [],
    log: true,
    maxPriorityFeePerGas,
  });

  const beacon = await deploy(beaconContract, {
    from: deployer,
    contract: 'UpgradeableBeacon',
    args: [garden.address],
    log: true,
    maxPriorityFeePerGas,
  });

  const gardenFactory = await deploy(gardenFactoryContract, {
    from: deployer,
    args: [controller.address, beacon.address],
    log: true,
    maxPriorityFeePerGas,
  });

  if (gardenFactory.newlyDeployed) {
    console.log(`Setting garden factory on controller ${gardenFactory.address}`);
    await (await controller.editGardenFactory(gardenFactory.address, { maxPriorityFeePerGas })).wait();
  }

  if (network.live && garden.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(gardenContract));
  }

  if (network.live && beacon.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(beaconContract));
  }

  if (network.live && gardenFactory.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(gardenFactoryContract));
  }
};

module.exports.tags = ['GardenFactory'];
