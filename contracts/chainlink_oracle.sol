// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
//import "@openzeppelin/contracts/access/AccessControl.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "./interfaces/BakiOracleInterface.sol";

contract BakiOracle is
    Ownable,
    ChainlinkClient,
    BakiOracleInterface
{
     using Chainlink for Chainlink.Request;

    bytes32 public constant DATA_FEED = keccak256("DATA_FEED");

    mapping(string => address) private zTokenAddress;
    mapping(address => uint256) private zTokenUSDValue;
    mapping(string => bool) private zTokenExists;

    string[] public zTokenList;
    uint256 public collateralUSD;
    string  baseURL;
    mapping(bytes32 => string) public requestIdToZTokenName;
    mapping(bytes32 => string) private requestIdToCurrencySymbol;
     bytes32 private jobId;
    uint256 private fee;
    int256 private MULTIPLIER = 1000;

    constructor(
        address _datafeed,
        address _zusd,
        address _zngn,
        address _zzar,
        address _zxaf
    ) {
        
        string[4] memory default_currencies = ["zusd", "zngn", "zzar", "zxaf"];
        //_setupRole(DATA_FEED, _datafeed);
        //_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        baseURL = "b499-37-60-75-197.ngrok-free.app/api/v1/fetch-rates?base=";
        // Chainlink setup
        setChainlinkToken(0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846);
        setChainlinkOracle(0x74EcC8Bdeb76F2C6760eD2dc8A46ca5e581fA656);
        jobId = "ca98366cc7314957b8c012c72f05aeeb";
        fee = 0.01 * 10**18; // 0,1 * 10**18 (Varies by network and job)

        zTokenAddress["zusd"] = _zusd;
        zTokenExists["zusd"] = true;
        zTokenAddress["zngn"] = _zngn;
        zTokenExists["zngn"] = true;
        zTokenAddress["zzar"] = _zzar;
        zTokenExists["zzar"] = true;
        zTokenAddress["zxaf"] = _zxaf;
        zTokenExists["zxaf"] = true;

        zTokenList = default_currencies;
    }

    event AddZToken(string indexed _name, address _address);
    event RemoveZToken(string indexed _name);
    event SetZTokenUSDValue(string indexed _name, uint256 _value);
    event SetZCollateralUSD(uint256 _value);

 

     function setZTokenUSDValue(string calldata _base, string[] calldata _symbols) external returns (bytes32[] memory requestIds ) {
       // address zToken = getZToken(_name);

        //require(hasRole(DATA_FEED, msg.sender), "Caller is not data_feed");
        //require(zTokenExists[_name], "zToken does not exist");
        //require(zToken != address(0), "zToken does not exist");

        requestIds = new bytes32[](_symbols.length);

        for(uint i = 0; i < _symbols.length; i++) {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfillZTokenUSDValue.selector);
        
        // Construct the URL dynamically using the _base and _symbols parameters
        string memory url = string(abi.encodePacked(baseURL, _base, "&symbols=", _symbols[i]));
        request.add("get", url);
        
        // Set the path to find the desired data in the API response
        string memory path = string(abi.encodePacked("rates", _symbols[i]));
        request.add("path", path);

        int256 timesAmount = 10**18;
        request.addInt("times", timesAmount);

        // Sends the request
        bytes32 requestId = sendChainlinkRequest(request, fee);

        // Store the _name and currency symbol associated with this request ID
        requestIdToZTokenName[requestId] = string(abi.encodePacked("z", _symbols[i]));
        requestIdToCurrencySymbol[requestId] = _symbols[i];

        requestIds[i] = requestId;
    }

    
    }

    function setZCollateralUSD() external returns (bytes32 requestId) {
       // require(hasRole(DATA_FEED, msg.sender), "Caller is not data_feed");
       Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfillZCollateralUSDValue.selector);
       string memory url = string(abi.encodePacked("https://min-api.cryptocompare.com/data/pricemultifull?fsyms=USD&tsyms=USDC"));
        request.add("get", url);
        string memory path = string(abi.encodePacked("RAW,USD,USDC,PRICE"));
        request.add("path", path);
        request.addInt("times", MULTIPLIER);
        return sendChainlinkRequest(request, fee);

    }

 
    function fulfillZTokenUSDValue(
        bytes32 _requestId,
        uint256 _price
    ) public recordChainlinkFulfillment(_requestId) {
        // Retrieve the _name and currency symbol associated with this request ID
        string memory _name = requestIdToZTokenName[_requestId];

        // Get the zToken address and update the price
        address zToken = getZToken(_name);
        require(zToken != address(0), "zToken does not exist");
        zTokenUSDValue[zToken] = _price;
        emit SetZTokenUSDValue(_name, _price);
        // Optionally, delete the mapping entries if they're no longer needed
        delete requestIdToZTokenName[_requestId];
        delete requestIdToCurrencySymbol[_requestId];
    }

    function fulfillZCollateralUSDValue(
        bytes32 _requestId,
        uint256 _price
    ) public recordChainlinkFulfillment(_requestId) {
        if (_price > 1000) {
            collateralUSD = 1000;
        } else {
            collateralUSD = _price;
        }

        emit SetZCollateralUSD(_price);
    }

    function addZToken(
        string calldata _name,
        address _address
    ) external onlyOwner {
        require(_address != address(0), "Address is invalid");
        require(!checkIfTokenExists(_name), "zToken already exists");

        zTokenAddress[_name] = _address;
        zTokenExists[_name] = true;
        zTokenList.push(_name);

        emit AddZToken(_name, _address);
    }

    function getZToken(string memory _name) public view returns (address) {
        require(zTokenAddress[_name] != address(0), "zToken does not exist");

        return zTokenAddress[_name];
    }

    function getZTokenList() external view returns (string[] memory) {
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

    function checkIfTokenExists(
        string calldata _name
    ) public view returns (bool) {
        require(!zTokenExists[_name], "zToken already exists");

        bytes32 nameHash = keccak256(bytes(_name));

        for (uint256 i = 0; i < zTokenList.length; i++) {
            if (keccak256(bytes(zTokenList[i])) == nameHash) {
                return true;
            }
        }
        return false;
    }


    function getZTokenUSDValue(
        string calldata _name
    ) external view returns (uint256) {
        address zToken = getZToken(_name);

        require(zToken != address(0), "zToken does not exist");

        return zTokenUSDValue[zToken];
    }
   

    function toLowerCase(string memory str) public pure returns (string memory) {
    bytes memory bStr = bytes(str);
    bytes memory bLower = new bytes(bStr.length);
    for (uint i = 0; i < bStr.length; i++) {
        // Uppercase character ASCII range: 65 to 90
        if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
            bLower[i] = bytes1(uint8(bStr[i]) + 32);
        } else {
            bLower[i] = bStr[i];
        }
    }
    return string(bLower);
}

     function setBaseUrl(string calldata baseurl) external {
        baseURL =  baseurl;
     }
}
