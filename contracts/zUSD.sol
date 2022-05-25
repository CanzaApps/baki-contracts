// SPDX-License-Identified: MIT
 
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ZUSD is ERC20 {

    constructor() ERC20("zUSD", "zUSD"){
      _mint(msg.sender, 1000000 ether);
    }

    // Mint this much tokens to the caller
    // OnlyVault modifier
    function mint(uint256 _amount) external  
    {
        _mint(msg.sender, _amount);
    }
}

