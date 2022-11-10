// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/BakiOracleInterface.sol";

contract BakiOracle is Ownable, BakiOracleInterface {
    uint256 _NGNUSD;
    uint256 _XAFUSD;
    uint256 _ZARUSD;

    function setNGNUSD(uint256 _value) external onlyOwner {
        _NGNUSD = _value;
    }

    function setXAFUSD(uint256 _value) external onlyOwner {
        _XAFUSD = _value;
    }

    function setZARUSD(uint256 _value) external onlyOwner {
        _ZARUSD = _value;
    }

    function NGNUSD() external view override returns (uint256) {
        return _NGNUSD;
    }

    function XAFUSD() external view override returns (uint256) {
        return _XAFUSD;
    }

    function ZARUSD() external view override returns (uint256) {
        return _ZARUSD;
    }
}
