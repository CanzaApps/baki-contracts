// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IVault {
    // #### Struct definitions
    struct Vault {
        uint256 collateralAmount; // The amount of collateral held by the vault contract
        uint256 debtAmount; // The amount of stable coin that was minted against the collateral
    }

    // Event definition
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Deposit(uint256 amountDeposited, uint256 amountMinted);

    // #### Function definitions
    function mint(uint256 amountToMint) external payable;

    function deposit(uint256 amountToDeposit) external payable;

    function getVault(address userAddress)
        external
        view
        returns (Vault memory vault);

    function estimateCollateralAmount(uint256 repaymentAmount)
        external
        view
        returns (uint256 collateralAmount);
}
