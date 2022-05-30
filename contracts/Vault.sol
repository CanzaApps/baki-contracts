// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Vault is IVault, Ownable {
    IERC20 public immutable token;
    uint256 public totalSupply;
    mapping(address => Vault) public vaults;

    constructor(address _token) {
        token = IERC20(_token);
    }

    /**
     * Mints stable coin to the vault contract.
     * @param amountToMint The amount of stable coin to mint.
     */
    function send(uint256 amountToMint, uint256 amountToDeposit)
        external
        payable
        returns (uint256 minted)
    {
        require(
            amountToDeposit <= msg.sender.balance,
            "Amount to deposit must be greater than 0"
        );
        uint256 condition = (vaults[msg.sender].collateralAmount +
            amountToDeposit) / (vaults[msg.sender].debtAmount + amountToMint);
        require(
            condition > 15,
            "You do not have any colateral, deposit to  mint"
        );
        totalSupply += amountToMint;
        token.transfer(msg.sender, amountToMint);
        // check if minted
        return 1;
        // check if minted
        return 0;
    }

    /** 
    @notice Allows a user to deposit cUSD collateral in exchange for some amount of zUSD.
    @param amountToDeposit  The amount of cUSD the user sent in the transaction
     */
    function deposit(uint256 amountToDeposit, uint256 _mintAmount)
        external
        payable
        override
    {
        uint256 amountToMint = amountToDeposit; // => for now
        token.transferFrom(msg.sender, address(this), amountToDeposit);
        vaults[msg.sender].collateralAmount += amountToDeposit;
        vaults[msg.sender].debtAmount += amountToMint; // for now
        emit Deposit(amountToDeposit, amountToMint);
    }

    // function controller(uint256 amountToDeposit, uint256 _mintAmount)
    //     external
    //     override
    // {
    // if (_mintAmount > 0) {
    //     uint256 result = mint(_mintAmount, amountToDeposit);
    //     require(result == 1, "Mint passed");
    //     deposit(amountToDeposit, _mintAmount);
    // } else {
    //     deposit(amountToDeposit, _mintAmount);
    // }
    // }

    function getVault(address userAddress)
        external
        view
        override
        returns (Vault memory vault)
    {
        return vaults[userAddress];
    }

    function estimateCollateralAmount(uint256 repaymentAmount)
        external
        view
        override
        returns (uint256 collateralAmount)
    {
        // this will get the rate from the oracle and estimate the collateralAmount
    }
}
