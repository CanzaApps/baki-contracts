// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
/**
* @dev Oracle interface
 */
interface BakiOracleInterface {
    /**
    * @dev get each exRates 
     */


    function getZTokenUSDValue(string calldata _name) external view returns(uint256);

    function getZToken(string calldata _name) external view returns(address);

    function getZTokenList() external view returns(string[] memory);

    function collateralUSD() external view returns (uint256);
}