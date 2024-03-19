// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @dev Interface of the zTokens used by Baki
 */
interface ZTokenInterface {
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
