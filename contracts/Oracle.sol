// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

contract PriceOracle is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    bytes32 private jobId;
    uint256 private fee;
    uint256 public CELOUSD;
    uint256 public NGNUSD;
    uint256 public CFAUSD;
    uint256 public ZARUSD;
    string constant baseURL = "https://baki-price-oracle.herokuapp.com/api/v1";

    event NewQuery(string description);
    event ResultObtained(bytes32 indexed requestId, uint256 result);

    /**
     * @notice Initialize the link token and target oracle
     *
     * Alfajores Testnet details:
     * Link Token: 0xa36085F69e2889c224210F603D836748e7dC0088
     * Oracle: 0x74EcC8Bdeb76F2C6760eD2dc8A46ca5e581fA656 (Chainlink DevRel)
     * jobId: ca98366cc7314957b8c012c72f05aeeb
     *
     */
    constructor() ConfirmedOwner(msg.sender) {
        setChainlinkToken(0xa36085F69e2889c224210F603D836748e7dC0088);
        setChainlinkOracle(0x74EcC8Bdeb76F2C6760eD2dc8A46ca5e581fA656);
        jobId = "ca98366cc7314957b8c012c72f05aeeb";
        fee = 0.01 * 10**18; // 0,1 * 10**18 (Varies by network and job)
    }

    // ############################################################################# CFAUSD #############################################################################

    function submitCELOUSD(string memory url)
        public
        returns (bytes32 requestId)
    {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillCELOUSD.selector
        );

        // Set the URL to perform the GET request on
        req.add("get", url);
        req.add("path", "data"); // Chainlink nodes 1.0.0 and later support this format

        // Multiply the result by 1000000000000000000 to remove decimals
        int256 timesAmount = 10**18;
        req.addInt("times", timesAmount);

        // Sends the request
        return sendChainlinkRequest(req, fee);
    }

    /**
     * Receive the response in the form of uint256
     */
    function fulfillCELOUSD(bytes32 _requestId, uint256 result)
        public
        recordChainlinkFulfillment(_requestId)
    {
        emit ResultObtained(_requestId, result);
        CELOUSD = result;
    }

    // ############################################################################# NGNUSD #############################################################################

    function submitNGNUSD(string memory url)
        public
        returns (bytes32 requestId)
    {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillNGNUSD.selector
        );

        // Set the URL to perform the GET request on
        req.add("get", url);
        req.add("path", "data"); // Chainlink nodes 1.0.0 and later support this format

        // Multiply the result by 1000000000000000000 to remove decimals
        int256 timesAmount = 10**18;
        req.addInt("times", timesAmount);

        // Sends the request
        return sendChainlinkRequest(req, fee);
    }

    /**
     * Receive the response in the form of uint256
     */
    function fulfillNGNUSD(bytes32 _requestId, uint256 result)
        public
        recordChainlinkFulfillment(_requestId)
    {
        emit ResultObtained(_requestId, result);
        NGNUSD = result;
    }

    // ############################################################################# CFAUSD #############################################################################
    function submitCFAUSD(string memory url)
        public
        returns (bytes32 requestId)
    {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillCFAUSD.selector
        );

        // Set the URL to perform the GET request on
        req.add("get", url);
        req.add("path", "data"); // Chainlink nodes 1.0.0 and later support this format

        // Multiply the result by 1000000000000000000 to remove decimals
        int256 timesAmount = 10**18;
        req.addInt("times", timesAmount);

        // Sends the request
        return sendChainlinkRequest(req, fee);
    }

    /**
     * Receive the response in the form of uint256
     */
    function fulfillCFAUSD(bytes32 _requestId, uint256 result)
        public
        recordChainlinkFulfillment(_requestId)
    {
        emit ResultObtained(_requestId, result);
        CFAUSD = result;
    }

    // ############################################################################# ZARUSD #############################################################################
    function submitZARUSD(string memory url)
        public
        returns (bytes32 requestId)
    {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillCFAUSD.selector
        );

        // Set the URL to perform the GET request on
        req.add("get", url);
        req.add("path", "data"); // Chainlink nodes 1.0.0 and later support this format

        // Multiply the result by 1000000000000000000 to remove decimals
        int256 timesAmount = 10**18;
        req.addInt("times", timesAmount);

        // Sends the request
        return sendChainlinkRequest(req, fee);
    }

    /**
     * Receive the response in the form of uint256
     */
    function fulfillZARUSD(bytes32 _requestId, uint256 result)
        public
        recordChainlinkFulfillment(_requestId)
    {
        emit ResultObtained(_requestId, result);
        ZARUSD = result;
    }

    // create a request
    function createRequest(string memory pricePair) public {
        string memory url = string(abi.encodePacked(baseURL, "/", pricePair));
        emit NewQuery("Requesting price data");
        if (
            keccak256(abi.encodePacked(pricePair)) ==
            keccak256(abi.encodePacked("CELOUSD"))
        ) {
            submitCELOUSD(url);
        } else if (
            keccak256(abi.encodePacked(pricePair)) ==
            keccak256(abi.encodePacked("NGNUSD"))
        ) {
            submitNGNUSD(url);
        } else if (
            keccak256(abi.encodePacked(pricePair)) ==
            keccak256(abi.encodePacked("CFAUSD"))
        ) {
            submitCFAUSD(url);
        } else if (
            keccak256(abi.encodePacked(pricePair)) ==
            keccak256(abi.encodePacked("ZARUSD"))
        ) {
            submitZARUSD(url);
        }
    }

    function getCELOUSD() public view returns (uint256) {
        return CELOUSD;
    }

    function getNGNUSD() public view returns (uint256) {
        return NGNUSD;
    }

    function getCFAUSD() public view returns (uint256) {
        return CFAUSD;
    }

    function getZARUSD() public view returns (uint256) {
        return ZARUSD;
    }
}
