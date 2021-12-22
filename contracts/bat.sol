pragma solidity ^0.8.10;
// SPDX-License-Identifier: MIT

//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Bat is ERC20{
        constructor() public ERC20("Basic Attention Token", "BAT"){} 
        function faucet(address to, uint amount) external {
                _mint(to, amount);
  }
}
