// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/BakiOracleInterface.sol";

contract BakiOracle is Ownable, BakiOracleInterface {
    uint256 public NGNUSD;
    uint256 public XAFUSD;
    uint256 public ZARUSD;
    uint256 public collateralUSD;

    function setNGNUSD(uint256 _value) external onlyOwner {
        NGNUSD = _value;
    }

    function setXAFUSD(uint256 _value) external {
        XAFUSD = _value;
    }

    function setZARUSD(uint256 _value) external onlyOwner {
        ZARUSD = _value;
    }

    function setCollateralUSD(uint256 _value) external onlyOwner {
        collateralUSD = _value;
    } 

}
