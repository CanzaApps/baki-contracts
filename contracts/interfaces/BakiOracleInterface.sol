// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @dev Oracle interface
 */
interface BakiOracleInterface {
    /**
     * @dev get each exRates
     */
    function NGNUSD() external view returns (uint256);

    function XAFUSD() external view returns (uint256);

    function ZARUSD() external view returns (uint256);

    function NGNXAF() external view returns (uint256);

    function ZARXAF() external view returns (uint256);

    function NGNZAR() external view returns (uint256);

    function collateralUSD() external view returns (uint256);
}
