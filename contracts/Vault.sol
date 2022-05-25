// The manager access control
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract Vault {
    IERC20 public immutable token;
    uint public totalSupply;
    address public owner;
    mapping(address => uint) public balanceOf;
    event Transfer(address indexed from, address indexed to, uint value);

   constructor(address _token) {
        owner = msg.sender;
        token = IERC20(_token);
    }

    function _mint(address _to, uint _value) private {
        totalSupply += _value;
        balanceOf[_to] += _value;
    }
    
    function _burn(address _from, uint _value) private {
        totalSupply -= _value;
        balanceOf[_from] -= _value;
    }

    function deposit(uint _amount) external {
        uint amountCUSD;
        _mint(msg.sender, amountCUSD);
        token.transferFrom(msg.sender, address(this), _amount);
    }
    
}

