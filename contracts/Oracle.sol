// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/BakiOracleInterface.sol";

contract BakiOracle is Ownable, BakiOracleInterface {

    mapping(string => address) private zTokenAddress;
    mapping(address => uint256) private zTokenUSDValue;
    mapping(string => bool) private zTokenExists;
    
    string[] public zTokenList;
    uint256 public collateralUSD;

    event AddZToken(string indexed _name, address _address);
    event RemoveZToken(string indexed _name);
    event SetZTokenUSDValue(string indexed _name, uint256 _value);
    event SetZCollateralUSD(uint256 _value);

    function addZToken(string calldata _name, address _address) external onlyOwner {
        require(_address != address(0), "Address is invalid");
        require(!checkIfTokenExists(_name), "zToken already exists");

        zTokenAddress[_name] = _address;
        zTokenExists[_name] = true;
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
        require(zTokenExists[_name], "zToken does not exists");

        delete zTokenAddress[_name];
        zTokenExists[_name] = false;

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

    function checkIfTokenExists(string calldata _name) public view returns(bool){
        require(!zTokenExists[_name], "zToken already exists");
        
        bytes32 nameHash = keccak256(bytes(_name));

        for (uint256 i = 0; i < zTokenList.length; i++) {
            if (keccak256(bytes(zTokenList[i])) == nameHash) {
                return true;
            }
        }
        return false;
    }


    function setZTokenUSDValue(
        string calldata _name,
        uint256 _value
    ) external onlyOwner {
        address zToken = getZToken(_name);

        require(zToken != address(0), "zToken does not exist");
        require(_value >= 1, "Invalid value");

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
