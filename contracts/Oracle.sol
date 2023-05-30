// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/BakiOracleInterface.sol";

contract BakiOracle is
    BakiOracleInterface,
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    uint256 public NGNUSD;
    uint256 public XAFUSD;
    uint256 public ZARUSD;
    uint256 public collateralUSD;
    uint256 public NGNXAF;
    uint256 public ZARXAF;
    uint256 public NGNZAR;

    function oracle_init() external initializer {
        __Ownable_init();
    }

    function setNGNUSD(uint256 _value) external onlyOwner {
        NGNUSD = _value;
    }

    function setXAFUSD(uint256 _value) external onlyOwner {
        XAFUSD = _value;
    }

    function setZARUSD(uint256 _value) external onlyOwner {
        ZARUSD = _value;
    }

    function setNGNXAF(uint256 _value) external onlyOwner {
        NGNXAF = _value;
    }

    function setZARXAF(uint256 _value) external onlyOwner {
        ZARXAF = _value;
    }

    function setNGNZAR(uint256 _value) external onlyOwner {
        NGNZAR = _value;
    }

    function setZCollateralUSD(uint256 _value) external onlyOwner {
        if (_value > 1000) {
            collateralUSD = 1000;
        } else {
            collateralUSD = _value;
        }
    }
}
