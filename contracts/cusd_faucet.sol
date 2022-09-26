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

    function SetCUSD(address CUSDAddress) public onlyOwner {
        cUSD = CUSDAddress;
    }

    function getCUSD(address receiver) public {
        CUSDInterface(cUSD).mint(receiver, 1000000000 ether);
    }
}
