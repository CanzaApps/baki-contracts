// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/BakiOracleInterface.sol";

contract BakiOracle is Ownable, AccessControl, BakiOracleInterface {

    bytes32 public constant DATA_FEED = keccak256("DATA_FEED");

    mapping(string => address) private zTokenAddress;
    mapping(address => uint256) private zTokenUSDValue;
    
    string[] public zTokenList;
    uint256 public collateralUSD;

    constructor (address _datafeed, address _zusd, address _zngn, address _zzar, address _zxaf) {
        string[4] memory default_currencies = ["zusd", "zngn", "zzar", "zxaf"];
        _setupRole(DATA_FEED, _datafeed);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        zTokenAddress["zusd"] = _zusd;
        zTokenAddress["zngn"] = _zngn;
        zTokenAddress["zzar"] = _zzar;
        zTokenAddress["zxaf"] = _zxaf;
       
        zTokenList = default_currencies;
    }

    event AddZToken(string indexed _name, address _address);
    event RemoveZToken(string indexed _name);
    event SetZTokenUSDValue(string indexed _name, uint256 _value);
    event SetZCollateralUSD(uint256 _value);

    function addZToken(string calldata _name, address _address) external onlyOwner {
        require(_address != address(0), "Address is invalid");
        require(!checkIfTokenExists(_name), "zToken already exists");

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
        uint len = zTokenList.length;

        for (uint256 i; i < len; i++) {
            if (keccak256(bytes(zTokenList[i])) == nameHash) {
                index = i;
                break;
            }
        }

        if (index < len) {
            zTokenList[index] = zTokenList[len - 1];
            zTokenList.pop();
        }

        emit RemoveZToken(_name);
    }

    function checkIfTokenExists(string calldata _name) public view returns(bool){
        bytes32 nameHash = keccak256(bytes(_name));
        uint len = zTokenList.length;

        for (uint256 i; i < len; i++) {
            if (keccak256(bytes(zTokenList[i])) == nameHash) {
                return true;
            }
        }
        return false;
    }


    function setZTokenUSDValue(
        string calldata _name,
        uint256 _value
    ) external {
        address zToken = getZToken(_name);

        require(hasRole(DATA_FEED, msg.sender), "Caller is not data_feed");
        require(_value >= 1, "Invalid value");

        zTokenUSDValue[zToken] = _value;

        emit SetZTokenUSDValue(_name, _value);
    }

    function getZTokenUSDValue(
        string calldata _name
    ) external view returns (uint256) {
        address zToken = getZToken(_name);

        return zTokenUSDValue[zToken];
    }

    function setZCollateralUSD(uint256 _value) external {
        require(hasRole(DATA_FEED, msg.sender), "Caller is not data_feed");

        if (_value > 1000) {
            collateralUSD = 1000;
        } else {
            collateralUSD = _value;
        }

        emit SetZCollateralUSD(_value);
    }
}
