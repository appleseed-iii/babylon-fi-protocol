pragma solidity >=0.6.0 <0.7.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./FundToken.sol";
import "./HedgeFund.sol";

contract Holder {
    struct HedgeFundMapping {
        HedgeFund hedgeFund;
        uint256 index;
    }

    address public protocolManager;

    // Hedge Funds List
    HedgeFundMapping[] public hedgeFunds;
    uint256 public currentHedgeFundIndex = 1;
    uint256 public totalHedgeFunds = 0;
    mapping(string => uint256) public hedgeFundsMapping;

    // Functions
    constructor() public {
        protocolManager = msg.sender;
    }

    modifier onlyProtocol {
        require(
            msg.sender == protocolManager,
            "Only protocol can add strategies"
        );
        _;
    }

    function addHedgeFund(string memory _name) public onlyProtocol {
        require(
            hedgeFundsMapping[_name] == 0,
            "The hedge fund already exists."
        );
        HedgeFund newHedgeFund = new HedgeFund(_name, true, msg.sender);
        hedgeFunds.push(
            HedgeFundMapping(newHedgeFund, currentHedgeFundIndex + 1)
        );
        hedgeFundsMapping[_name] = currentHedgeFundIndex;
        currentHedgeFundIndex++;
        totalHedgeFunds++;
    }

    function disableHedgeFund(string memory _name) public onlyProtocol {
        uint256 atIndex = hedgeFundsMapping[_name];
        HedgeFundMapping storage _hedgeFundMapping = hedgeFunds[atIndex - 1];
        require(
            _hedgeFundMapping.hedgeFund.active(),
            "The hedge fund needs to be active."
        );
        _hedgeFundMapping.hedgeFund.setActive(false);
        totalHedgeFunds--;
    }

    function reenableHedgeFund(string memory _name) public onlyProtocol {
        uint256 atIndex = hedgeFundsMapping[_name];
        HedgeFundMapping storage _hedgeFundMapping = hedgeFunds[atIndex - 1];
        require(
            !_hedgeFundMapping.hedgeFund.active(),
            "The hedge fund needs to be disabled."
        );
        _hedgeFundMapping.hedgeFund.setActive(true);
        totalHedgeFunds++;
    }

    function getHedgeFund(string memory _name)
        public
        view
        returns (
            string memory name,
            bool active,
            uint256 index
        )
    {
        uint256 atIndex = hedgeFundsMapping[_name];
        HedgeFundMapping storage _hedgeFundMapping = hedgeFunds[atIndex - 1];
        return (
            _hedgeFundMapping.hedgeFund.name(),
            _hedgeFundMapping.hedgeFund.active(),
            _hedgeFundMapping.index
        );
    }

    function transferEth(address payable _to, uint256 amount) private {
        // Call returns a boolean value indicating success or failure.
        // This is the current recommended method to use.
        (bool sent, ) = _to.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }
}
