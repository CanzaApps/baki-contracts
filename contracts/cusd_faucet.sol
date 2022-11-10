// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

interface CUSDInterface {
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

contract CUSDFaucet is Ownable {
    address public cUSD;

    event SetCUSD(address _address);

    function setCUSD(address _address) public onlyOwner {
        require(_address != address(0), "address cannot be a zero address");

        cUSD = _address;

        emit SetCUSD(_address);
    }

    function getCUSD(address receiver) public returns(bool) {
        return CUSDInterface(cUSD).mint(receiver, 1000000000 ether);
    }
}
