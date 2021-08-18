const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { increaseTime, increaseBlock, voteType, proposalState } = require('utils/test-helpers');

const { setupTests } = require('fixtures/GardenFixture');
const { impersonateAddress } = require('lib/rpc');

describe.only('BabylonGovernor', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let babGovernor;
  let timelockController;
  let babController;

  const version = '1';
  const tokenName = 'Babylon.Finance';
  const tokenSymbol = 'BABL';
  const value = from(0);

  let voter1;
  let voter2;
  let voter3;
  let voter4;

  async function getGovernorMock(period = 1, delay = 1) {
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;
    const signer = await getSigner(deployer);

    // We deploy a mock contract with shorter voting period
    const mockGovernor = await deploy('BabylonGovernorMock', {
      from: deployer,
      args: [bablToken.address, timelockController.address, delay, period],
      log: true,
    });
    return await ethers.getContractAt('BabylonGovernor', mockGovernor.address, signer);
  }

  async function grantRoles(contract) {
    const { deployer } = await getNamedAccounts();
    const signer = await getSigner(deployer);

    const PROPOSER_ROLE = await timelockController.PROPOSER_ROLE();
    const EXECUTOR_ROLE = await timelockController.EXECUTOR_ROLE();

    await (await timelockController.connect(deployer).grantRole(PROPOSER_ROLE, contract.address)).wait();
    await (await timelockController.connect(deployer).grantRole(EXECUTOR_ROLE, contract.address)).wait();
  }

  async function claimTokens(voters) {
    for (const voter of voters) {
      await bablToken.connect(voter.voter).claimMyTokens();
    }
  }

  async function selfDelegation(voters) {
    for (const voter of voters) {
      await bablToken.connect(voter.voter).delegate(voter.voter.address);
      await increaseBlock(1);
    }
  }

  async function castVotes(id, voters) {
    for (const voter of voters) {
      await babGovernor.connect(voter.voter).castVote(id, ethers.BigNumber.from(voter.support));
    }
  }

  async function getProposal(governor) {
    const ABI = ['function enableBABLMiningProgram()'];
    const iface = new ethers.utils.Interface(ABI);
    const encodedData = iface.encodeFunctionData('enableBABLMiningProgram');
    const description = '<proposal description>';
    const descriptionHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('<proposal description>'));

    const id = await governor.hashProposal([babController.address], [value], [encodedData], descriptionHash);

    const proposalObject = {
      id,
      args: [[babController.address], [value], [encodedData], description],
      voters: [
        { voter: voter1, support: voteType.For, reason: 'This is nice' },
        { voter: voter2, support: voteType.For },
        { voter: voter3, support: voteType.Against },
        { voter: voter4, support: voteType.Abstain },
      ],
    };

    await claimTokens(proposalObject.voters);

    await selfDelegation(proposalObject.voters);
    return proposalObject;
  }

  beforeEach(async () => {
    ({
      owner,
      signer1,
      signer2,
      signer3,
      bablToken,
      babGovernor,
      timelockController,
      babController,
    } = await setupTests()());

    voter1 = await impersonateAddress('0x3E7c4E57A1dc4dD4bBE81bEFBe3E437f69619DaB'); // 20K
    voter2 = await impersonateAddress('0x06601571AA9D3E8f5f7CDd5b993192618964bAB5'); // 15K
    voter3 = await impersonateAddress('0x83f4622A18e38bE297e089fB055Dd5123bb0b279'); // Team 24K
    voter4 = await impersonateAddress('0x232775eAD28F0C0c750A097bA77302E7d84efd3B'); // Team 17K
  });

  describe('deployment', function () {
    it('should successfully deploy Governor Babylon contract', async function () {
      const tokenSupply = await bablToken.totalSupply();
      expect(await babGovernor.name()).to.be.equal('BabylonGovernor');
      expect(await babGovernor.version()).to.be.equal(version);
      expect(await babGovernor.token()).to.be.equal(bablToken.address);
      expect(await babGovernor.votingDelay()).to.be.equal('1');
      expect(await babGovernor.votingPeriod()).to.be.equal(45818);
      expect(await babGovernor.quorum(0)).to.be.equal(tokenSupply.div(25)); // 4% of totalSupply BABL
      expect(await babGovernor.proposalThreshold()).to.be.equal(tokenSupply.div(200)); // 0.5% of totalSupply BABL
      expect(await babGovernor.COUNTING_MODE()).to.be.equal('support=bravo&quorum=bravo');
      expect(await babGovernor.timelock()).to.be.equal(timelockController.address);

      // Check the linked BABL Token
      expect(await bablToken.name()).to.be.equal(tokenName);
      expect(await bablToken.symbol()).to.be.equal(tokenSymbol);
    });
  });

  describe('hashProposal', function () {
    it('can hash', async function () {
      const { id } = await getProposal(babGovernor);
      expect(id.toString()).to.equal('31592073516640214093428763406121273246927507816899979568469470593665780044126');
    });
  });

  describe('propose', function () {
    it('can NOT propose below a proposal threshold', async function () {
      const { args } = await getProposal(babGovernor);
      // propose
      await expect(
        babGovernor.connect(signer1)['propose(address[],uint256[],bytes[],string)'](...args),
      ).to.be.revertedWith('GovernorCompatibilityBravo: proposer votes below proposal threshold');
    });

    it('make a valid proposal', async function () {
      const { id, args } = await getProposal(babGovernor);

      // propose
      await babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      const [
        proposalId,
        proposerAddress,
        eta,
        startBlock,
        endBlock,
        forVotes,
        againstVotes,
        abstainVotes,
        canceled,
        executed,
      ] = await babGovernor.proposals(id);

      expect(proposalId).to.be.equal(id);
      expect(proposerAddress).to.be.equal(voter1.address);
      expect(eta).to.be.equal(0);
      expect(startBlock).to.be.equal(await babGovernor.proposalSnapshot(id));
      expect(endBlock).to.be.equal(await babGovernor.proposalDeadline(id));
      expect(forVotes).to.be.equal(0);
      expect(againstVotes).to.be.equal(0);
      expect(abstainVotes).to.be.equal(0);
      expect(canceled).to.be.equal(false);
      expect(executed).to.be.equal(false);
    });
  });

  describe('castVoteWithReason', function () {});

  describe('castVoteBySig', function () {
    it.skip('can cast a vote by sig', async function () {
      // TODO
    });
  });

  describe('castVote', function () {
    it('can cast a vote', async function () {
      const { id, args, voters } = await getProposal(babGovernor);

      // propose
      await babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      // 4 blocks to reach the block where the voting starts
      await increaseBlock(4);

      await castVotes(id, voters);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await babGovernor.proposals(id);

      // Check all voters have voted
      expect(await babGovernor.hasVoted(id, voter1.address)).to.be.equal(true);
      expect(await babGovernor.hasVoted(id, voter2.address)).to.be.equal(true);
      expect(await babGovernor.hasVoted(id, voter3.address)).to.be.equal(true);
      expect(await babGovernor.hasVoted(id, voter4.address)).to.be.equal(true);

      // Check all votes are counted for For, Against and Abstain
      expect(forVotes).to.eq(eth(35000));
      expect(againstVotes).to.eq(eth(24750));
      expect(abstainVotes).to.eq(eth(17000));

      // Other params
      expect(eta).to.be.eq(0);
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      expect(await babGovernor.state(id)).to.eq(1);
    });

    it('can NOT cast a vote before votes start', async function () {
      const mockGovernor = await getGovernorMock(10, 10);
      const { id, args } = await getProposal(mockGovernor);

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      await expect(mockGovernor.connect(voter1).castVote(id, voteType.For)).to.be.revertedWith(
        'Governor: vote not currently active',
      );
      expect(await mockGovernor.proposalDeadline(id)).to.be.gt((await ethers.provider.getBlock()).number);
    });

    it('can NOT cast a vote after voting period ends', async function () {
      const mockGovernor = await getGovernorMock(10);
      const { id, args } = await getProposal(mockGovernor);

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      // We vote after the deadline
      await increaseBlock(14);

      await expect(mockGovernor.connect(voter1).castVote(id, voteType.For)).to.be.revertedWith(
        'Governor: vote not currently active',
      );
      expect(await mockGovernor.proposalDeadline(id)).to.be.lte((await ethers.provider.getBlock()).number);
    });
  });

  describe('queue', function () {
    it.skip('can queue proposal', async function () {
      const mockGovernor = await getGovernorMock(10);
      const { id, args, votes } = await getProposal(mockGovernor);

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      // 4 blocks to reach the block where the voting starts
      await increaseBlock(4);

      await castVotes(id, votes);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);

      /** 
      const mockGovernor = await getGovernorMock(10);
      // await grantRoles(mockGovernor);
      const [proposalObject, id] = await getProposal(voter1, mockGovernor);

      // propose
      await mockGovernor
        .connect(voter1)
        ['propose(address[],uint256[],bytes[],string)'](...proposalObject.proposal);
    
      console.log('block before', (await ethers.provider.getBlock()).number.toString());

      await increaseBlock(4);
      console.log('block after 1', (await ethers.provider.getBlock()).number.toString());
      const [
        proposalId,
        proposerAddress,
        eta,
        startBlock,
        endBlock,
        forVotes,
        againstVotes,
        abstainVotes,
        canceled,
        executed,
      ] = await mockGovernor.proposals(id);
      console.log('CHECK', await mockGovernor.proposals(id));
      await castVotes(proposalObject, id);
      console.log('block after 2', (await ethers.provider.getBlock()).number.toString());

      await increaseBlock(5);
      console.log('block last', (await ethers.provider.getBlock()).number.toString());
      */
    });
  });
  describe('execute', function () {});
});
