// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/** 
* @dev Interface of the zTokens to be used by Baki
*/
interface ZTokenInterface {
    /**
    * @dev Amount of zTokens to be minted for a user
    * requires onlyVault modifier
    */
    function mint(address _address, uint256 _amount) external returns(bool);

    /**
    * @dev Amount of zTokens to be burned after swap/repay functions
    * requires onlyVault modifier
    */
    function burn(address _address, uint256 _amount) external returns(bool);

    /**
    * @dev Amount of a particular zTokens minted by Vault contract for a user
    */
    function getUserMintValue(address _address) external returns(uint256);

    /**
    * @dev Global amount of a particular zTokens minted by Vault contract for all users
    */
    function getGlobalMint() external returns(uint256);
}
