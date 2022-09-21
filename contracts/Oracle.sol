// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

contract PriceOracle is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    bytes32 private jobId;
    uint256 private fee;
    uint256 public NGNUSD;
    uint256 public CFAUSD;
    uint256 public ZARUSD;
    uint256 public XRATE;
    string public baseURL;

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
        setChainlinkToken(0x01BE23585060835E02B77ef475b0Cc51aA1e0709);
        setChainlinkOracle(0xf3FBB7f3391F62C8fe53f89B41dFC8159EE9653f);
        jobId = "ca98366cc7314957b8c012c72f05aeeb";
        fee = 0.25 * 10**18; // 0,1 * 10**18 (Varies by network and job)
    }

    // ############################################################################# NGNUSD #############################################################################

    function _submitNGNUSD(string memory url)
        internal
        returns (bytes32 requestId)
    {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this._fulfillNGNUSD.selector
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
    function _fulfillNGNUSD(bytes32 _requestId, uint256 result)
        public
        recordChainlinkFulfillment(_requestId)
    {
        emit ResultObtained(_requestId, result);
        NGNUSD = result;
    }

    // ############################################################################# CFAUSD #############################################################################
    function _submitCFAUSD(string memory url)
        internal
        returns (bytes32 requestId)
    {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this._fulfillCFAUSD.selector
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
    function _fulfillCFAUSD(bytes32 _requestId, uint256 result)
        public
        recordChainlinkFulfillment(_requestId)
    {
        emit ResultObtained(_requestId, result);
        CFAUSD = result;
    }

    // ############################################################################# ZARUSD #############################################################################
    function _submitZARUSD(string memory url)
        internal
        returns (bytes32 requestId)
    {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this._fulfillZARUSD.selector
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
    function _fulfillZARUSD(bytes32 _requestId, uint256 result)
        public
        recordChainlinkFulfillment(_requestId)
    {
        emit ResultObtained(_requestId, result);
        ZARUSD = result;
    }

    // ############################################################################# XRATES #############################################################################
    function _submitXRATE(string memory url)
        internal
        returns (bytes32 requestId)
    {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this._fulfillXRATE.selector
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
    function _fulfillXRATE(bytes32 _requestId, uint256 result)
        public
        recordChainlinkFulfillment(_requestId)
    {
        emit ResultObtained(_requestId, result);
        XRATE = result;
    }

    // create a request
    function createRequest(string memory _target, string memory base) external {
        string memory pair = string(abi.encodePacked(_target, "/", base));
        string memory url = string(abi.encodePacked(baseURL, "/", pair));
        emit NewQuery("Requesting price data");
        if (
            keccak256(abi.encodePacked(pair)) ==
            keccak256(abi.encodePacked("NGN/USD"))
        ) {
            _submitNGNUSD(url);
        } else if (
            keccak256(abi.encodePacked(pair)) ==
            keccak256(abi.encodePacked("CFA/USD"))
        ) {
            _submitCFAUSD(url);
        } else if (
            keccak256(abi.encodePacked(pair)) ==
            keccak256(abi.encodePacked("ZAR/USD"))
        ) {
            _submitZARUSD(url);
        } else {
            _submitXRATE(url);
        }
    }

    // set Base URL
    function updateBaseURL(string memory _url) public onlyOwner {
        baseURL = _url;
    }
}
