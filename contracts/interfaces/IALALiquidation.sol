// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;


interface IALALiquidation {
    function liquidate(uint256 _amountToLiquidate, uint256 _auctionId) external;
}