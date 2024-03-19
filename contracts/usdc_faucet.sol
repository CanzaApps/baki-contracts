// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";

interface USDCInterface {
    /**
     * @dev Amount of zTokens to be minted for a user
     * requires onlyVault modifier
     */
    function mint(address _address, uint256 _amount) external returns (bool);

    /**
     * @dev Amount of zTokens to be burned after swap/repay functions
     * requires onlyVault modifier
     */
    function burn(address _address, uint256 _amount) external returns (bool);
}

contract USDCFaucet is Ownable {
    address public USDC;

    event SetUSDC(address _address);

    function setUSDC(address _address) public onlyOwner {
        require(_address != address(0), "address cannot be a zero address");

        USDC = _address;

        emit SetUSDC(_address);
    }

    function getUSDC(address receiver) public returns (bool) {
        bool success = USDCInterface(USDC).mint(receiver, 1000000000 ether);

        return success;
    }
}
