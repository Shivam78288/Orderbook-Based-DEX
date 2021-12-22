pragma solidity ^0.8.10;
// SPDX-License-Identifier: MIT

//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract Dai is ERC20{
        constructor() public ERC20("Dai", "DAI") {}
        function faucet(address to, uint amount) external {
             _mint(to, amount);
  }
}
