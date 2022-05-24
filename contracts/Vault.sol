
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


contract Vault {
    address public owner;
    uint public totalzCF;
    mapping(address => uint) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint value);

    constructor(address _beneficiary) public {
        owner = msg.sender;
    }

    function _mint(address _to, uint _value) private {
        totalSupply += _value;
        balanceOf[_to] += _value;
    }
    
    function _burn(address _from, uint _value) private {
        totalSupply -= _value;
        balanceOf[_from] -= _value;
    }

    
   
}