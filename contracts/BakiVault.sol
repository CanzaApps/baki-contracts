// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BakiVault is Ownable {
    // Collateral address
    address private collateral;
    address private zUSD;
    address private zCFA;
    address private zNGN;
    address private zZAR;
    struct IUser {
        uint256 userCollateralBalance;
        uint256 userDebtOutstanding;
        uint256 collaterizationRatio;
    }
    mapping(address => IUser) User;

    // Transaction events
    event TransferReceived(address _from, uint256 _amount);
    event TransferSent(address _from, address _destAddr, uint256 _amount);

    // Collaterization ratio value
    uint256 private collaterizationRatioValue = 1.5 * 10**3;

    /**
     * Net Global Mint
     * Maps zUSD address => cumulative mint value for all users
     */
    uint256 private netMintGlobal;

    // Net mint User
    mapping(address => uint256) netMintUser;

    // Build Struct to Hold Exchange rates by Address

    struct exchangeRatesData {
        address zToken;
        uint256 ExRate;
    }

    //create array of structs

    exchangeRatesData[] public storedExchangeRateData;

    // Set exchange rates and addresses

    mapping(address => uint256) public ExRate;

    function setexchangeRates(address _zTokenAddress, uint256 _exchangeRate)
        public
    {
        ExRate[_zTokenAddress] = _exchangeRate;
    }

    //Get exchange rates based on address of contract

    function getexchangeRate(address _address) public view returns (uint256) {
        return ExRate[_address];
    }

    // Deposit and mint function
    function depositAndMint(uint256 _depositAmount, uint256 _mintAmount)
        public
        payable
    {
        uint256 mintAmount = _getVal(_mintAmount);
        uint256 depositAmount = _getVal(_depositAmount);

        // Checking user ballance
        require(
            IERC20(collateral).balanceOf(msg.sender) >= depositAmount,
            "Insufficient balance"
        );
        require(depositAmount >= mintAmount, "Insufficient collateral");
        // uint256 fakeUserNetMint = netMintUser[msg.sender] + mintAmount;
        // uint256 fakeGlobalNetMint = netMintGlobal + mintAmount;
        // uint256 fakeUserDebt = _updateUserDebtOutstanding(fakeUserNetMint, fakeGlobalNetMint);
        // uint256 fakeUserCollateralBalance = User[msg.sender].userCollateralBalance + depositAmount;

        // require(fakeUserCollateralBalance*10**3/fakeUserDebt >= collaterizationRatioValue);

        // Depositing the collateral
        IERC20(collateral).transferFrom(
            msg.sender,
            address(this),
            depositAmount
        );
        User[msg.sender].userCollateralBalance += depositAmount;
        emit TransferReceived(msg.sender, depositAmount);

        if (netMintUser[msg.sender] == 0 && netMintGlobal == 0) {
            // Minting zUSD
            IERC20(zUSD).transfer(msg.sender, mintAmount);
            netMintUser[msg.sender] += mintAmount;
            netMintGlobal += mintAmount;
            _updateUserDebtOutstanding(netMintUser[msg.sender], netMintGlobal);
            User[msg.sender].collaterizationRatio = ((10**3 *
                User[msg.sender].userCollateralBalance) /
                User[msg.sender].userDebtOutstanding);
            emit TransferSent(address(this), msg.sender, mintAmount);
        } else if (netMintUser[msg.sender] == 0) {
            /**
             * Get User outstanding debt
             */
            _updateUserDebtOutstanding(netMintUser[msg.sender], netMintGlobal);
            /**
             * Check collateral ratio
             */
            User[msg.sender].collaterizationRatio = ((10**3 *
                User[msg.sender].userCollateralBalance) /
                User[msg.sender].userDebtOutstanding);

            if (
                User[msg.sender].collaterizationRatio >=
                collaterizationRatioValue
            ) {
                IERC20(zUSD).transfer(msg.sender, mintAmount);
                netMintUser[msg.sender] += mintAmount;
                netMintGlobal += mintAmount;
                _updateUserDebtOutstanding(
                    netMintUser[msg.sender],
                    netMintGlobal
                );
                emit TransferSent(address(this), msg.sender, mintAmount);
            }
        }
    }

    // Deposit Collateral
    function deposit(uint256 _depositAmount) public payable {
        uint256 depositAmount = _getVal(_depositAmount);
        // Checking user ballance
        require(
            IERC20(collateral).balanceOf(msg.sender) >= depositAmount,
            "Insufficient funds"
        );

        // Depositing the collateral
        IERC20(collateral).transferFrom(
            msg.sender,
            address(this),
            depositAmount
        );
        User[msg.sender].userCollateralBalance += depositAmount;
        emit TransferReceived(msg.sender, depositAmount);
    }

    // Mint zUSD
    function mintZUSD(uint256 _mintAmount) public payable {
        uint256 mintAmount = _getVal(_mintAmount);
        require(
            User[msg.sender].userCollateralBalance > mintAmount,
            "Insufficient Collateral"
        );
        // Minting zUSD
        IERC20(zUSD).transfer(msg.sender, mintAmount);
        User[msg.sender].userDebtOutstanding += mintAmount;
        netMintGlobal += mintAmount;
        emit TransferSent(address(this), msg.sender, mintAmount);
    }

    // set ZUSD address
    function setZUSDAddress(address token) public onlyOwner {
        zUSD = token;
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

    // set Collateral address
    function setCollateralAddress(address token) public onlyOwner {
        collateral = token;
    }

    // Get user debt
    function getUserDebt() public view returns (uint256) {
        return User[msg.sender].userDebtOutstanding;
    }

    // Get user Collateral
    function getUserCollateral() public view returns (uint256) {
        return User[msg.sender].userCollateralBalance;
    }

    // Get real value
    function _getVal(uint256 _value) internal virtual returns (uint256) {
        return _value * 10**18;
    }

    /**
     * Get User Outstanding Debt
     */
    function _updateUserDebtOutstanding(
        uint256 _netMintUserzUSDValue,
        uint256 _netMintGlobalzUSDValue
    ) internal virtual returns (uint256) {
        if (_netMintGlobalzUSDValue > 0) {
            User[msg.sender].userDebtOutstanding =
                (_netMintUserzUSDValue / _netMintGlobalzUSDValue) *
                (IERC20(zUSD).totalSupply() +
                    IERC20(zNGN).totalSupply() /
                    getexchangeRate(zNGN) +
                    IERC20(zCFA).totalSupply() /
                    getexchangeRate(zCFA) +
                    IERC20(zZAR).totalSupply() /
                    getexchangeRate(zZAR));
        } else {
            User[msg.sender].userDebtOutstanding = 0;
        }

        return User[msg.sender].userDebtOutstanding;
    }

    // function withdraw(uint amount, address payable destAddr) public onlyOwner {
    //     require(amount <= balance, "Insufficient funds");
    //     destAddr.transfer(amount);
    //     balance -= amount;
    //     emit TransferSent(msg.sender, destAddr, amount);
    // }

    // function transferERC20(IERC20 token, address to, uint256 amount) public {
    //     uint256 erc20balance = token.balanceOf(address(this));
    //     require(amount <= erc20balance, "balance is low");
    //     token.transfer(to, amount);
    //     emit TransferSent(msg.sender, to, amount);
    // }
}
