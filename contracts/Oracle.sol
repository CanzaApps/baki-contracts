// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/BakiOracleInterface.sol";

contract BakiOracle is Ownable, BakiOracleInterface {
    mapping(address => uint256) public zTokenUSDValue;
    address[] public zTokenList;
    uint256 public collateralUSD;

    function addZToken(address _address) external onlyOwner {
        zTokenList.push(_address);
    }

    function setZTokenUSDValue(
        address _address,
        uint256 _value
    ) external onlyOwner {
        zTokenUSDValue[_address] = _value;
    }

    function getZTokenUSDValue(
        address _address
    ) external view returns (uint256) {
        return zTokenUSDValue[_address];
    }

    function setZCollateralUSD(uint256 _value) external onlyOwner {
        if (_value > 1000) {
            collateralUSD = 1000;
        } else {
            collateralUSD = _value;
        }
    }

    function getZTokenList() external view returns (address[] memory) {
        return zTokenList;
    }
}
