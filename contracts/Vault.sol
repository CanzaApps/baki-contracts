// The manager access control
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract Vault {
    IERC20 public immutable token;
    uint256 public totalSupply;
    address public owner;
    mapping(address => uint256) public balanceOf;
    event Transfer(address indexed from, address indexed to, uint256 value);

   constructor(address _token) {
        owner = msg.sender;
        token = IERC20(_token);
    }

    function _mint(address _to, uint256 _value) private {
        totalSupply += _value;
        balanceOf[_to] += _value;
    }
    
    function _burn(address _from, uint256 _value) private {
        totalSupply -= _value;
        balanceOf[_from] -= _value;
    }

    function deposit(uint256 _amount) external {
        uint256 amountCUSD;
        _mint(msg.sender, amountCUSD);
        token.transferFrom(msg.sender, address(this), _amount);
    }
    
}

