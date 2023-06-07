// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
* @dev Oracle interface
 */
interface BakiOracleInterface {
    /**
    * @dev get each exRates 
     */
    function getZTokenUSDValue(address _address) external view returns(uint256);

    function getZTokenList() external view returns(address[] memory);

    function collateralUSD() external view returns (uint256);
}