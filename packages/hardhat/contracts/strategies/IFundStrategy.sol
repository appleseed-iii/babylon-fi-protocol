pragma solidity >=0.7.0 <0.9.0;

interface IFundStrategy {

  function contractImpl() external view returns (address);
  function getFunds() external view returns (uint);

  // Yearn
  function want() external view returns (address);

  function deposit() external;

  // NOTE: must exclude any tokens used in the yield
  // Controller role - withdraw should return to Controller
  function withdraw(address) external;

  // Controller | Vault role - withdraw should always return to Vault
  function withdraw(uint256) external;

  function skim() external;

  // Controller | Vault role - withdraw should always return to Vault
  function withdrawAll() external returns (uint256);

  function balanceOf() external view returns (uint256);

}
