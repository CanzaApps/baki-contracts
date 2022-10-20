// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
* @dev Oracle interface
 */
interface BakiOracleInterface {
    /**
    * @dev get each exRates 
     */
    function NGNUSD() external view returns (uint);

    function XAFUSD() external view returns (uint);

    function ZARUSD() external view returns (uint);
}