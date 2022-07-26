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

    uint256 private collaterizationRatioValue = 1.5 * 10**3;
    /**
     * Net User Mint
     * Maps user address => cumulative mint value
     */
    mapping(address => uint256) private netMintUser;

    /**
     * Net Global Mint
     */
    uint256 private netMintGlobal;

    /**
    * map users to accrued fee balance 
    * store 75% swap fee to be shared by minters
    * store 25% swap fee seaparately
    * user => uint256
     */
    mapping(address => uint256) private userAccruedFeeBalance;

    uint256 public globalMintersFee;

    uint256 public treasuryFee;

    address treasuryWallet = 0x6F996Cb36a2CB5f0e73Fc07460f61cD083c63d4b;

    /**
    * Store minters addresses as a list
    */
    address[] public mintersAddresses;

    /** 
    @notice Allows a user to deposit cUSD collateral in exchange for some amount of zUSD.
     _depositAmount  The amount of cUSD the user sent in the transaction
     */
    function depositAndMint(uint256 _depositAmount, uint256 _mintAmount) public payable {
        
        require(IERC20(collateral).balanceOf(msg.sender) >= _depositAmount, "Insufficient balance");
       
        // transfer cUSD tokens from user wallet to vault contract
        IERC20(collateral).transferFrom(
            msg.sender,
            address(this),
            _depositAmount
        );
        User[msg.sender].userCollateralBalance += _depositAmount;

        /**
        * if this is user's first mint, add to minters list
        * Mint zUSD without checking collaterization ratio
        */
     if (netMintUser[msg.sender] == 0) {
        require(_depositAmount >= _mintAmount, "Insufficient collateral");

        mintersAddresses.push(msg.sender);

        _mint(zUSD, msg.sender, _mintAmount);

        netMintUser[msg.sender] += _mintAmount;

        netMintGlobal += _mintAmount;

        _updateUserDebtOutstanding(netMintUser[msg.sender], netMintGlobal);

        User[msg.sender].collaterizationRatio = (10**3 * User[msg.sender].userCollateralBalance / User[msg.sender].userDebtOutstanding);
     }
     else {
        /**
        * Get User outstanding debt
        */
        _updateUserDebtOutstanding(netMintUser[msg.sender], netMintGlobal);
        /** 
        * Check collateral ratio
        */
        User[msg.sender].collaterizationRatio = (10**3 * User[msg.sender].userCollateralBalance / User[msg.sender].userDebtOutstanding);


        if (User[msg.sender].collaterizationRatio >= collaterizationRatioValue) {
          _mint(zUSD, msg.sender, _mintAmount);

          netMintUser[msg.sender] += _mintAmount;

          netMintGlobal += _mintAmount;

          _updateUserDebtOutstanding(netMintUser[msg.sender], netMintGlobal);
              
        } 
     }
  
   }

    /**
     * Allows a user to swap zUSD for other zTokens using their exchange rates
     */
    function swap(
        uint256 _amount,
        address _zTokenFrom,
        address _zTokenTo
    ) public {
        require(
            IERC20(_zTokenFrom).balanceOf(msg.sender) >= _amount,
            "Insufficient balance"
        );
        uint256 mintAmount;
        uint256 amountToBeSwapped;
        uint256 swapFee = (3 * _amount) / 10;
        uint256 swapFeeInUsd = swapFee * getExchangeRate(_zTokenFrom);

        /**
         * Get the USD values of involved zTokens 
         * Handle minting of new tokens and burning of user tokens
         */
        uint256 zTokenFromPerUsd = getExchangeRate(_zTokenFrom);
        uint256 zTokenToPerUsd = getExchangeRate(_zTokenTo);

        amountToBeSwapped = _amount - swapFee;
        mintAmount = amountToBeSwapped * (zTokenFromPerUsd/zTokenToPerUsd);

        _burn(_zTokenFrom, msg.sender, _amount);

        _mint(_zTokenTo, msg.sender, mintAmount);

        /**
        * Handle swap fees and rewards
        */
        uint256 globalMintersFeePerTransaction = (3 * swapFeeInUsd) / 4;
        globalMintersFee += globalMintersFeePerTransaction;

        treasuryFeePerTransaction += (1 * swapFeeInUsd) / 4;
        treasuryFee += treasuryFeePerTransaction;

        /**
        * Send the treasury amount from User to a treasury wallet
         */
        IERC20(zUSD).transferFrom(
            msg.sender,
            treasuryWallet,
            treasuryFeePerTransaction
        );

        for (uint i = 0; i < mintersAddresses.length; i++){
            userAccruedFeeBalance[mintersAddresses[i]] = (netMintUser[mintersAddresses[i]]/netMintGlobal) * globalMintersFeePerTransaction;
        }
    }

    /** 
    * Allows to user to repay and/or withdraw their collateral
    */
    function repayAndWithdraw(uint256 _amountToRepay, uint256 _amountToWithdraw, address _zToken, uint exchangeRate) public payable {
    
      uint256 amountToRepayinUSD = _repay(_amountToRepay, _zToken, exchangeRate);

      require(amountToRepayinUSD >= _amountToWithdraw, "Insufficient Collateral");

      /**
      * Substract withdraw from current net mint value and assign new mint value
      */
      uint256 amountToSubtract = (netMintUser[msg.sender] * amountToRepayinUSD/User[msg.sender].userDebtOutstanding);

      netMintUser[msg.sender] -= amountToSubtract;

      netMintGlobal -= amountToSubtract;

      uint256 AdjustedDebt; 

       /**
        *  Check if Net Mint User and Net Mint Global = 0 
        */
     if (netMintUser[msg.sender] == 0) {
       /**
        * Get User outstanding debt
        * If 0 replace netMintUser[msg.sender][zUSD] with 1
        */
        AdjustedDebt = 0;

     } else {
        /**
        * Get User outstanding debt
        */
       // _updateUserDebtOutstanding(netMintUser[msg.sender][zUSD], netMintGlobal[zUSD]);

        AdjustedDebt = netMintUser[msg.sender]/netMintGlobal*((IERC20(zUSD).totalSupply() + IERC20(zNGN).totalSupply() / zNGNzUSDPair + IERC20(zCFA).totalSupply() / zCFAzUSDPair + IERC20(zZAR).totalSupply() / zZARzUSDPair) - amountToRepayinUSD);

     }
        
        /** 
        * Check collateral ratio
        */

        uint256 AdjustedCollateralizationRatio;

        if(AdjustedDebt > 0){
            AdjustedCollateralizationRatio = 10**3 * (User[msg.sender].userCollateralBalance - _amountToWithdraw) / AdjustedDebt;
        }
        

        if(AdjustedCollateralizationRatio >= collaterizationRatioValue || AdjustedDebt == 0) {
          _burn(zUSD, msg.sender, amountToRepayinUSD);


        _updateUserDebtOutstanding(netMintUser[msg.sender], netMintGlobal);
        
        if(netMintGlobal > 0){
            User[msg.sender].collaterizationRatio =  10**3 * (User[msg.sender].userCollateralBalance / User[msg.sender].userDebtOutstanding );
        }
        /** 
        * @TODO - Implement actual transfer of cUSD _amountToWithdraw value
        */
        IERC20(collateral).transferFrom(
            address(this),
            msg.sender,
            _amountToWithdraw
        );
    }
    }

    /**
    * get and set exchange rate data of zTokens per USD
     */
    mapping( address => uint256) public ratePerUsd;


    function setExchangeRate(address _address, uint256 _rate) public {
       ratePerUsd[_address] = _rate; 
    }

    function getExchangeRate(address _address ) public view returns (uint256) {
        return ratePerUsd[_address];
    }

    /**
     * @dev Returns the minted token value for a particular user
     */
    function getNetUserMintValue(address _address)
        public
        view
        returns (uint256)
    {
        return netMintUser[_address];
    }

    /**
     * @dev Returns the total minted token value
     */
    function getNetGlobalMintValue()
        public
        view
        returns (uint256)
    {
        return netMintGlobal;
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
     * Get Total Supply of zTokens
     */
    function getTotalSupply(address _address) public view returns (uint256) {
        return IERC20(_address).totalSupply();
    }

    /**
    * view minters addresses
    */
    function viewMintersAddress() public view returns (address[] memory) {
        return mintersAddresses;
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
        // require(IERC20(_zToken).balanceOf(msg.sender) >= _amount, "Insufficient balance");
        uint256 zUSDMintAmount;

      /** 
      * Get the exchange rate between zToken and USD
      */
          exchangeRate = getExchangeRate(_zToken);
          
          zUSDMintAmount = _amount * 1/(exchangeRate);

        _burn(_zToken, msg.sender, _amount);

        _mint(zUSD, msg.sender, zUSDMintAmount); 


        return zUSDMintAmount;
    }

    /** 
    * Get User Outstanding Debt
    */
    function _updateUserDebtOutstanding(uint256 _netMintUserzUSDValue, uint256 _netMintGlobalzUSDValue) internal virtual returns(uint256){

        if(_netMintGlobalzUSDValue > 0){
            User[msg.sender].userDebtOutstanding = _netMintUserzUSDValue/_netMintGlobalzUSDValue * (IERC20(zUSD).totalSupply() + 
            IERC20(zNGN).totalSupply() / getExchangeRate(zNGN) + 
            IERC20(zCFA).totalSupply() / getExchangeRate(zCFA) + 
            IERC20(zZAR).totalSupply() / getExchangeRate(zZAR));
            
        }else{

            User[msg.sender].userDebtOutstanding = 0;
        }
        
        return User[msg.sender].userDebtOutstanding;
    }

    /**
    * Helper function to test the impact of a transaction i.e mint, burn, deposit or withdrawal by a user
     */
    // function _testImpact(uint256 _zUsdMintAmount, uint256 _zUsdBurnAmount,uint256  _depositAmount, uint256 _withdrawalAmount) internal virtual returns(bool){
    //     /**
    //     * Initialize test variables
    //      */
    //     uint256 getCollateralValue;
    //     uint256 collateralMovement;
    //     uint256 netMintMovement;
    //     /**
    //     * Adjuested Net Mint is initialized from netMintUser[msg.sender]
    //      */
    //     uint256 adjustedNetMint = netMintUser[msg.sender];
    //     /**
    //     * Global Net Mint is initialized from netMintGlobal
    //      */
    //     uint256 globalNetMint = netMintGlobal;

    //     uint256 collaterization_ratio = 1.5;

    //     collateralMovement = _depositAmount - _withdrawalAmount + User[msg.sender].userCollateralBalance;

    //     netMintMovement = _zUsdMintAmount - (netMintUser[msg.sender] * (_zUsdBurnAmount / User[msg.sender].userDebtOutstanding));

        
    // }

    //test function
    function getUserDebtOutstanding(
        uint256 _netMintUserzUSDValue,
        uint256 _netMintGlobalzUSDValue,
        uint256 totalSupply,
        uint256 USDSupply
    ) public returns (uint256) {
        User[msg.sender].userDebtOutstanding =
            (_netMintUserzUSDValue / _netMintGlobalzUSDValue) *
            (USDSupply +
                totalSupply /
                zNGNzUSDPair +
                totalSupply /
                zCFAzUSDPair +
                totalSupply /
                zZARzUSDPair);
        return User[msg.sender].userDebtOutstanding;
    }
}
