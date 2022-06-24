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
  
    constructor() {
    }

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

    // mapping(address => uint256) private userCollateralBalance;
    // mapping(address => uint256) private userDebtOutstanding;
    // mapping(address => uint256) private collaterizationRatio

    uint256 private collaterizationRatioValue = 1.5 * 10**3;

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
    function deposit(uint256 _depositAmount, uint256 _mintAmount) public payable {
        
        require(IERC20(collateral).balanceOf(msg.sender) >= _depositAmount, "Insufficient balance");
        require(_depositAmount >= _mintAmount, "Insufficient collateral");
       
        // transfer cUSD tokens from user wallet to vault contract
        // IERC20(collateral).transferFrom(msg.sender, address(this), _amount);

        User[msg.sender].userCollateralBalance += _depositAmount;

        /**
        *  Check if Net Mint User and Net Mint Global = 0 
        */
     if (netMintUser[msg.sender][zUSD] == 0 && netMintGlobal[zUSD] == 0) {
       /**
        * Mint zUSD without checking 
        */

        _mint(zUSD, msg.sender, _mintAmount);

        netMintUser[msg.sender][zUSD] += _mintAmount;

        netMintGlobal[zUSD] += _mintAmount;

        _updateUserDebtOutstanding(netMintUser[msg.sender][zUSD], netMintGlobal[zUSD]);

        User[msg.sender].collaterizationRatio = (10**3 * User[msg.sender].userCollateralBalance / User[msg.sender].userDebtOutstanding);
        
     } else if (netMintUser[msg.sender][zUSD] == 0 ) {
       /**
        * Get User outstanding debt
        */
        _updateUserDebtOutstanding(netMintUser[msg.sender][zUSD], netMintGlobal[zUSD]);
        /** 
        * Check collateral ratio
        */
        User[msg.sender].collaterizationRatio = (10**3 * User[msg.sender].userCollateralBalance / User[msg.sender].userDebtOutstanding);


        if (User[msg.sender].collaterizationRatio >= collaterizationRatioValue) {
          _mint(zUSD, msg.sender, _mintAmount);

          netMintUser[msg.sender][zUSD] += _mintAmount;

          netMintGlobal[zUSD] += _mintAmount;

          _updateUserDebtOutstanding(netMintUser[msg.sender][zUSD], netMintGlobal[zUSD]);
                  
        } 
     }
     else {
        /**
        * Get User outstanding debt
        */
        _updateUserDebtOutstanding(netMintUser[msg.sender][zUSD], netMintGlobal[zUSD]);
        /** 
        * Check collateral ratio
        */
        User[msg.sender].collaterizationRatio = (10**3 * User[msg.sender].userCollateralBalance / User[msg.sender].userDebtOutstanding);


        if (User[msg.sender].collaterizationRatio >= collaterizationRatioValue) {
          _mint(zUSD, msg.sender, _mintAmount);

          netMintUser[msg.sender][zUSD] += _mintAmount;

          netMintGlobal[zUSD] += _mintAmount;

          _updateUserDebtOutstanding(netMintUser[msg.sender][zUSD], netMintGlobal[zUSD]);
              
        } 
     }
   }

    /** 
    * Allows a user to swap zUSD for other zTokens using their exchange rates
    */
    function swap(uint256 _amount, address _zToken, uint exchangeRate) public {

      require(IERC20(_zToken).balanceOf(msg.sender) >= _amount, "Insufficient balance");

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
    function repayAndWithdraw(uint256 _amountToRepay, uint256 _amountToWithdraw, address _zToken, uint exchangeRate) public payable returns(string memory) {
    
      uint256 amountToRepayinUSD = _repay(_amountToRepay, _zToken, exchangeRate);

      require(amountToRepayinUSD >= _amountToWithdraw, "Insufficient Collateral");

      /**
      * Substract withdraw from current net mint value and assign new mint value
      */
      uint256 amountToSubtract = (amountToRepayinUSD/User[msg.sender].userDebtOutstanding) * netMintUser[msg.sender][zUSD];

      netMintUser[msg.sender][zUSD] -= amountToSubtract;

      netMintGlobal[zUSD] -= amountToSubtract;

       /**
        *  Check if Net Mint User and Net Mint Global = 0 
        */
     if (netMintUser[msg.sender][zUSD] == 0) {
       /**
        * Get User outstanding debt
        * If 0 replace netMintUser[msg.sender][zUSD] with 1
        */
        _updateUserDebtOutstanding(1, netMintGlobal[zUSD]);

     } else {
        /**
        * Get User outstanding debt
        */
        _updateUserDebtOutstanding(netMintUser[msg.sender][zUSD], netMintGlobal[zUSD]);
     }

        /** 
        * Check collateral ratio
        */
        User[msg.sender].collaterizationRatio = (User[msg.sender].userCollateralBalance/User[msg.sender].userDebtOutstanding) * 10**3;

        string memory result;

        if(User[msg.sender].collaterizationRatio >= collaterizationRatioValue) {
          _burn(zUSD, msg.sender, amountToRepayinUSD);

          _updateUserDebtOutstanding(netMintUser[msg.sender][zUSD], netMintGlobal[zUSD]);
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
    function changezCFAzUSDRate(uint rate) public onlyOwner {
        zCFAzUSDPair = rate;
    }

    function changezNGNzUSDRate(uint rate) public onlyOwner {
        zNGNzUSDPair = rate;
    }

    function changezZARzUSDRate(uint rate) public onlyOwner {
        zZARzUSDPair = rate;
    }

    /**
    * Get exchange rate values
    */
    function getzCFAzUSDRate() public view returns(uint){
        return zCFAzUSDPair;
    }

    function getzNGNzUSDRate() public view returns(uint){
        return zNGNzUSDPair;
    }

    function getzZARzUSDRate() public view returns(uint){
        return zZARzUSDPair;
    }

     /**
    * @dev Returns the minted token value for a particular user
     */
    function getNetUserMintValue(address _address, address _tokenAddress) public view returns(uint256) {
        return netMintUser[_address][_tokenAddress];
    }

    /**
    * @dev Returns the total minted token value
     */
    function getNetGlobalMintValue(address _tokenAddress) public view returns(uint256) {
        return netMintGlobal[_tokenAddress];
    }

    /**
    * Get User struct values 
    */
    function getCollaterizationRatio() public view returns(uint) {
        return User[msg.sender].collaterizationRatio;
    } 

    function getUserCollateralBalance() public view returns(uint256) {
        return User[msg.sender].userCollateralBalance;
    }

    function getUserDebtOutstanding() public view returns(uint256) {
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
    * Get Total Supply of zTokens
    */
    function getTotalSupply(address _address) public view returns(uint256){
        return IERC20(_address).totalSupply();
    }

    /**
    * Private functions
    */
    function _mint(address _tokenAddress, address _userAddress, uint256 _amount ) internal virtual {
        ZTokenInterface(_tokenAddress).mint(_userAddress, _amount);
    }

    function _burn(address _tokenAddress, address _userAddress, uint256 _amount ) internal virtual {
        ZTokenInterface(_tokenAddress).burn(_userAddress, _amount);
    }

    /** 
    * Allows a user swap back their zTokens to zUSD
    */
    function _repay(uint256 _amount, address _zToken, uint exchangeRate) internal virtual returns(uint256){

        // require(IERC20(_zToken).balanceOf(msg.sender) >= _amount, "Insufficient balance");

        uint256 zUSDMintAmount;

      /** 
      * Get the exchange rate between zToken and USD
      */
          zUSDMintAmount = _amount * 1/(exchangeRate);

        _burn(_zToken, msg.sender, _amount);

        _mint(zUSD, msg.sender, zUSDMintAmount);

        return zUSDMintAmount;
    }

    /** 
    * Get User Outstanding Debt
    */
    function _updateUserDebtOutstanding(uint256 _netMintUserzUSDValue, uint256 _netMintGlobalzUSDValue) internal virtual returns(uint256){

        User[msg.sender].userDebtOutstanding = _netMintUserzUSDValue/_netMintGlobalzUSDValue * (IERC20(zUSD).totalSupply() + 
        IERC20(zNGN).totalSupply() / zNGNzUSDPair + 
        IERC20(zCFA).totalSupply() / zCFAzUSDPair + 
        IERC20(zZAR).totalSupply() / zZARzUSDPair);

        return User[msg.sender].userDebtOutstanding;
    }

    //test function
    function getUserDebtOutstanding(uint256 _netMintUserzUSDValue, uint256 _netMintGlobalzUSDValue, uint256 totalSupply, uint256 USDSupply) public returns(uint256){
        User[msg.sender].userDebtOutstanding = _netMintUserzUSDValue/_netMintGlobalzUSDValue * (USDSupply + 
        totalSupply / zNGNzUSDPair + 
        totalSupply / zCFAzUSDPair + 
        totalSupply / zZARzUSDPair);

        return User[msg.sender].userDebtOutstanding;
    }
}

