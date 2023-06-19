// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

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

contract BakiOracle is Ownable, BakiOracleInterface {

    mapping(address => uint256) public zTokenUSDValue;
    address[] public zTokenList;
    uint256 public collateralUSD;

    event AddZToken(address indexed _address);
    event RemoveZToken(address indexed _address);
    event SetZTokenUSDValue(address indexed _address, uint256 _value);
    event SetZCollateralUSD(uint256 _value);

    function addZToken(address _address) external onlyOwner {
        require(_address != address(0), "Address is invalid");

        zTokenList.push(_address);

        emit AddZToken(_address);
    }

    function removeZToken(address _address) external onlyOwner {
        require(_address != address(0), "Address is invalid");

        uint256 index;

        for(uint256 i = 0; i < zTokenList.length; i++) {
            if(zTokenList[i] == _address) {
                index = i;
            }
        }

        zTokenList[index] = zTokenList[zTokenList.length-1];

        zTokenList.pop();

        emit RemoveZToken(_address);
    }

    function setZTokenUSDValue(
        address _address,
        uint256 _value
    ) external onlyOwner {
        zTokenUSDValue[_address] = _value;

        emit SetZTokenUSDValue(_address, _value);
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

        emit SetZCollateralUSD(_value);
    }

    function getZTokenList() external view returns (address[] memory) {
        return zTokenList;
    }
}
