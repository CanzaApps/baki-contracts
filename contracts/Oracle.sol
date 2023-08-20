// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/BakiOracleInterface.sol";

contract BakiOracle is Ownable, BakiOracleInterface {

    mapping(string => address) private zTokenAddress;
    mapping(address => uint256) private zTokenUSDValue;
    string[] public zTokenList;
    uint256 public collateralUSD;

    event AddZToken(string indexed _name, address _address);
    event RemoveZToken(string indexed _name);
    event SetZTokenUSDValue(string indexed _name, uint256 _value);
    event SetZCollateralUSD(uint256 _value);

    function addZToken(string calldata _name, address _address) external onlyOwner {
        require(_address != address(0), "Address is invalid");

        zTokenAddress[_name] = _address;

        zTokenList.push(_name);

        emit AddZToken(_name, _address);
    }

    function getZToken(string calldata _name) public view returns(address){
        require(zTokenAddress[_name] != address(0), "zToken does not exist");

        return zTokenAddress[_name];
    }

    function getZTokenList() external view returns(string[] memory){
        return zTokenList;
    }

     function removeZToken(string calldata _name) external onlyOwner {
        require(zTokenAddress[_name] != address(0), "zToken does not exist");

        delete zTokenAddress[_name];

        uint256 index;
        bytes32 nameHash = keccak256(bytes(_name));

        for (uint256 i = 0; i < zTokenList.length; i++) {
            if (keccak256(bytes(zTokenList[i])) == nameHash) {
                index = i;
                break;
            }
        }

        if (index < zTokenList.length) {
            zTokenList[index] = zTokenList[zTokenList.length - 1];
            zTokenList.pop();
        }

    emit RemoveZToken(_name);
}

    function setZTokenUSDValue(
        string calldata _name,
        uint256 _value
    ) external onlyOwner {
        address zToken = getZToken(_name);

        require(zToken != address(0), "zToken does not exist");

        zTokenUSDValue[zToken] = _value;

        emit SetZTokenUSDValue(_name, _value);
    }

    function getZTokenUSDValue(
        string calldata _name
    ) external view returns (uint256) {
        address zToken = getZToken(_name);

        require(zToken != address(0), "zToken does not exist");

        return zTokenUSDValue[zToken];
    }

    function setZCollateralUSD(uint256 _value) external onlyOwner {
        if (_value > 1000) {
            collateralUSD = 1000;
        } else {
            collateralUSD = _value;
        }

        emit SetZCollateralUSD(_value);
    }
}
