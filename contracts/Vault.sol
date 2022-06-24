// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ZTokenInterface.sol";

contract Vault is Ownable {
    /**
     * addresses of both the collateral and ztokens
     */
    address private collateral;
    address private zUSD;
    address private zCFA;
    address private zNGN;
    address private zZAR;

    /**
     * exchange rates of 1 USD to zTokens
     * Currency on the right is 1 value i.e the first currency(left) is compared to 1 value of the last (right) currency
     * TODO These should be fetched from an Oracle
     */

    uint256 private zCFAzUSDPair = 621;
    uint256 private zNGNzUSDPair = 415;
    uint256 private zZARzUSDPair = 16;

    constructor() {}

    /**
     * Collaterization ratio (in multiple of a 1000 to deal with float point)
     * Maps user address => value
     */
    struct IUser {
        uint256 userCollateralBalance;
        uint256 userDebtOutstanding;
        uint256 collaterizationRatio;
    }
    /**
     * userAddress => IUser
     */
    mapping(address => IUser) private User;

    uint256 private collaterizationRatioValue = 1500;

    /**
     * Net User Mint
     * Maps user address => zUSD address => cumulative mint value
     */
    mapping(address => mapping(address => uint256)) private netMintUser;

    /**
     * Net Global Mint
     * Maps zUSD address => cumulative mint value for all users
     */
    mapping(address => uint256) private netMintGlobal;

    /** 
    @notice Allows a user to deposit cUSD collateral in exchange for some amount of zUSD.
     _depositAmount  The amount of cUSD the user sent in the transaction
     */
    function deposit(uint256 _depositAmount, uint256 _mintAmount)
        public
        payable
        returns (string memory)
    {
        require(
            IERC20(collateral).balanceOf(msg.sender) >= _depositAmount,
            "Insufficient balance"
        );

        // transfer cUSD tokens from user wallet to vault contract
        // IERC20(collateral).transferFrom(msg.sender, address(this), _amount);

        User[msg.sender].userCollateralBalance += _depositAmount;

        /**
         * Get User outstanding debt
         */
        User[msg.sender].userDebtOutstanding =
            (netMintUser[msg.sender][zUSD] / netMintGlobal[zUSD]) *
            (IERC20(zUSD).totalSupply() +
                IERC20(zNGN).totalSupply() *
                zNGNzUSDPair +
                IERC20(zCFA).totalSupply() *
                zCFAzUSDPair +
                IERC20(zZAR).totalSupply() *
                zZARzUSDPair);

        /**
         * Check collateral ratio
         */
        User[msg.sender].collaterizationRatio =
            (User[msg.sender].userCollateralBalance /
                User[msg.sender].userDebtOutstanding) *
            1000;

        string memory result;

        if (
            User[msg.sender].collaterizationRatio <= collaterizationRatioValue
        ) {
            _mint(zUSD, msg.sender, _mintAmount);

            netMintUser[msg.sender][zUSD] += _mintAmount;

            netMintGlobal[zUSD] += netMintUser[msg.sender][zUSD];

            result = "Mint successful!";
        } else {
            result = "Insufficient collateral";
        }

        return result;
    }

    /**
     * Allows a user to swap zUSD for other zTokens using their exchange rates
     */
    function swap(
        uint256 _amount,
        address _zToken,
        uint256 exchangeRate
    ) public {
        require(
            IERC20(_zToken).balanceOf(msg.sender) >= _amount,
            "Insufficient balance"
        );

        uint256 mintAmount;
        /**
         * Get the exchange rate between zToken and USD
         */

        mintAmount = _amount * exchangeRate;

        _burn(zUSD, msg.sender, _amount);

        _mint(_zToken, msg.sender, mintAmount);
    }

    /**
     * Allows to user to repay and/or withdraw their collateral
     */
    function repayAndWithdraw(
        uint256 _amountToRepay,
        uint256 _amountToWithdraw,
        address _zToken,
        uint256 exchangeRate
    ) public payable returns (string memory) {
        uint256 amountToRepayinUSD = _repay(
            _amountToRepay,
            _zToken,
            exchangeRate
        );

        /**
         * Substract withdraw from current net mint value and assign new mint value
         */
        netMintUser[msg.sender][zUSD] -=
            (amountToRepayinUSD / User[msg.sender].userDebtOutstanding) *
            netMintUser[msg.sender][zUSD];

        netMintGlobal[zUSD] += netMintUser[msg.sender][zUSD];

        /**
         * Get User outstanding debt
         */
        User[msg.sender].userDebtOutstanding =
            (netMintUser[msg.sender][zUSD] / netMintGlobal[zUSD]) *
            (IERC20(zUSD).totalSupply() +
                IERC20(zNGN).totalSupply() *
                zNGNzUSDPair +
                IERC20(zCFA).totalSupply() *
                zCFAzUSDPair +
                IERC20(zZAR).totalSupply() *
                zZARzUSDPair);

        /**
         * Check collateral ratio
         */
        User[msg.sender].collaterizationRatio =
            (User[msg.sender].userCollateralBalance /
                User[msg.sender].userDebtOutstanding) *
            1000;

        string memory result;

        if (
            User[msg.sender].collaterizationRatio <= collaterizationRatioValue
        ) {
            _burn(zUSD, msg.sender, amountToRepayinUSD);

            /**
             * @TODO - Implement actual transfer of cUSD _amountToWithdraw value
             */
            result = "Withdraw is Valid!";
        } else {
            result = "Insufficient collateral";
        }
        return result;
    }

    /**
     * Change the currency pairs rate against 1 USD
     */

    function changezCFAzUSDRate(uint256 rate) public onlyOwner {
        zCFAzUSDPair = rate;
    }

    function changezNGNzUSDRate(uint256 rate) public onlyOwner {
        zNGNzUSDPair = rate;
    }

    function changezZARzUSDRate(uint256 rate) public onlyOwner {
        zZARzUSDPair = rate;
    }

    /**
     * Get User struct values
     */
    function getCollaterizationRatio() public view returns (uint256) {
        return User[msg.sender].collaterizationRatio;
    }

    function getUserCollateralBalance() public view returns (uint256) {
        return User[msg.sender].userCollateralBalance;
    }

    function getUserDebtOutstanding() public view returns (uint256) {
        return User[msg.sender].userDebtOutstanding;
    }

    /**
     * Add collateral address
     */
    function addCollateralAddress(address _address) public onlyOwner {
        collateral = _address;
    }

    /**
     * Add the four zToken contract addresses
     */
    function addZUSDAddress(address _address) public onlyOwner {
        zUSD = _address;
    }

    function addZNGNAddress(address _address) public onlyOwner {
        zNGN = _address;
    }

    function addZCFAAddress(address _address) public onlyOwner {
        zCFA = _address;
    }

    function addZZARAddress(address _address) public onlyOwner {
        zZAR = _address;
    }

    /**
     * Private functions
     */
    function _mint(
        address _tokenAddress,
        address _userAddress,
        uint256 _amount
    ) internal virtual {
        ZTokenInterface(_tokenAddress).mint(_userAddress, _amount);
    }

    function _burn(
        address _tokenAddress,
        address _userAddress,
        uint256 _amount
    ) internal virtual {
        ZTokenInterface(_tokenAddress).burn(_userAddress, _amount);
    }

    /**
     * Allows a user swap back their zTokens to zUSD
     */
    function _repay(
        uint256 _amount,
        address _zToken,
        uint256 exchangeRate
    ) internal virtual returns (uint256) {
        require(
            IERC20(_zToken).balanceOf(msg.sender) >= _amount,
            "Insufficient balance"
        );

        uint256 zUSDMintAmount;

        /**
         * Get the exchange rate between zToken and USD
         */
        zUSDMintAmount = (_amount * 1) / (exchangeRate);

        _burn(_zToken, msg.sender, _amount);

        _mint(zUSD, msg.sender, zUSDMintAmount);

        return zUSDMintAmount;
    }
}
