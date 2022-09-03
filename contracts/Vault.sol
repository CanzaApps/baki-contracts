// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ZTokenInterface.sol";

error TransferFailed();
error MintFailed();
error BurnFailed();

contract Vault is ReentrancyGuard, Ownable {
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

    uint256 public COLLATERIZATION_RATIO_THRESHOLD = 1.5 * 10**3;

    uint256 public LIQUIDATION_REWARD = 10;
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

    event Deposit(address indexed _account, address indexed _token, uint256 _depositAmount, uint256 _mintAmount);
    event Swap(address indexed _account, address indexed _zTokenFrom, address indexed _zTokenTo, uint256 _amount, uint256 _mintAmount);
    event Withdraw(address indexed _account, address indexed _token, uint256 _amountToRepay, uint256 _amountToWithdraw);
    event Liquidate(address indexed _account, uint256 indexed debt, uint256 indexed rewards, address liquidator);
    /** 
    @notice Allows a user to deposit cUSD collateral in exchange for some amount of zUSD.
     _depositAmount  The amount of cUSD the user sent in the transaction
     */
    function depositAndMint(
        uint256 _depositAmount, 
        uint256 _mintAmount,
        uint256 zNGNUSDRate, 
        uint256 zCFAUSDRate, 
        uint256 zZARUSDRate
    ) external nonReentrant payable {
        
        uint256 _depositAmountWithDecimal = _getDecimal(_depositAmount);
        uint256 _mintAmountWithDecimal = _getDecimal(_mintAmount);

        require(IERC20(collateral).balanceOf(msg.sender) >= _depositAmountWithDecimal, "Insufficient balance");
       
        // transfer cUSD tokens from user wallet to vault contract
        bool transferSuccess = IERC20(collateral).transferFrom(
            msg.sender,
            address(this),
            _depositAmountWithDecimal
        );

        if(!transferSuccess) revert TransferFailed();

        User[msg.sender].userCollateralBalance += _depositAmountWithDecimal;

        /**
        * if this is user's first mint, add to minters list
        * Mint zUSD without checking collaterization ratio
        */
     if (netMintUser[msg.sender] == 0) {
        require(_depositAmountWithDecimal >= _mintAmountWithDecimal, "Insufficient collateral");

        mintersAddresses.push(msg.sender);

        bool mintSuccess = _mint(zUSD, msg.sender, _mintAmountWithDecimal);

        if(!mintSuccess) revert MintFailed();

        netMintUser[msg.sender] += _mintAmountWithDecimal;

        netMintGlobal += _mintAmountWithDecimal;

       _updateUserDebtOutstanding(msg.sender, netMintUser[msg.sender], netMintGlobal, zNGNUSDRate, zCFAUSDRate, zZARUSDRate);

        User[msg.sender].collaterizationRatio = (10**3 * User[msg.sender].userCollateralBalance / User[msg.sender].userDebtOutstanding);
     }
     else {
        /**
        * Get User outstanding debt
        */
        _updateUserDebtOutstanding(msg.sender, netMintUser[msg.sender], netMintGlobal, zNGNUSDRate, zCFAUSDRate, zZARUSDRate);
        /** 
        * Check collateral ratio
        */
        User[msg.sender].collaterizationRatio = (10**3 * User[msg.sender].userCollateralBalance / User[msg.sender].userDebtOutstanding);

        require(User[msg.sender].collaterizationRatio >= COLLATERIZATION_RATIO_THRESHOLD, "Insufficient collateral");

        bool mintSuccess = _mint(zUSD, msg.sender, _mintAmountWithDecimal);

        if(!mintSuccess) revert MintFailed();

        netMintUser[msg.sender] += _mintAmountWithDecimal;

        netMintGlobal += _mintAmountWithDecimal;

        _updateUserDebtOutstanding(msg.sender, netMintUser[msg.sender], netMintGlobal, zNGNUSDRate, zCFAUSDRate, zZARUSDRate);
              
     }
  
        emit Deposit(msg.sender, collateral, _depositAmount, _mintAmount);
   }

    /**
     * Allows a user to swap zUSD for other zTokens using their exchange rates
     */
    function swap(
        uint256 _amount,
        address _zTokenFrom,
        address _zTokenTo,
        uint256 _zTokenFromUSDRate,
        uint256 _zTokenToUSDRate
    ) external nonReentrant {

        uint256 _amountWithDecimal = _getDecimal(_amount);

        require(
            IERC20(_zTokenFrom).balanceOf(msg.sender) >= _amountWithDecimal,
            "Insufficient balance"
        );
        uint256 mintAmount;
        uint256 amountToBeSwapped;
        uint256 swapFee = (3 * _amountWithDecimal) / 10;
        uint256 swapFeeInUsd = swapFee * _zTokenFromUSDRate;

        /**
         * Get the USD values of involved zTokens 
         * Handle minting of new tokens and burning of user tokens
         */
        amountToBeSwapped = _amountWithDecimal - swapFee;
        mintAmount = amountToBeSwapped * (_zTokenFromUSDRate/_zTokenToUSDRate);

        bool burnSuccess = _burn(_zTokenFrom, msg.sender, _amountWithDecimal);

        if(!burnSuccess) revert BurnFailed();

        bool mintSuccess = _mint(_zTokenTo, msg.sender, mintAmount);

        if(!mintSuccess) revert MintFailed();

        /**
        * Update User Outstanding Debt since we minted new tokens
        * @TODO - Handle this from the frontend i.e call _updateUserDebtOutstanding after each swap
         */
       
        /**
        * Handle swap fees and rewards
        */
        uint256 globalMintersFeePerTransaction = (3 * swapFeeInUsd) / 4;
        globalMintersFee += globalMintersFeePerTransaction;

        uint256 treasuryFeePerTransaction = (1 * swapFeeInUsd) / 4;
        treasuryFee += treasuryFeePerTransaction;

        /**
        * Send the treasury amount from User to a treasury wallet
         */
        IERC20(zUSD).transferFrom(
            msg.sender,
            treasuryWallet,
            treasuryFeePerTransaction
        );

        /**
        * @TODO - Send the remaining fee to all minters
         */
        for (uint i = 0; i < mintersAddresses.length; i++){
            userAccruedFeeBalance[mintersAddresses[i]] = (netMintUser[mintersAddresses[i]]/netMintGlobal) * globalMintersFeePerTransaction;
        }
        emit Swap(msg.sender, _zTokenFrom, _zTokenTo, _amount, mintAmount);
    }

    /** 
    * Allows to user to repay and/or withdraw their collateral
    */
    function repayAndWithdraw(
        uint256 _amountToRepay, 
        uint256 _amountToWithdraw, 
        address _zToken, 
        uint _zTokenUSDRate,
        uint256 zNGNUSDRate, 
        uint256 zCFAUSDRate, 
        uint256 zZARUSDRate
    ) external nonReentrant payable {

      uint256 _amountToRepayWithDecimal = _getDecimal(_amountToRepay);
      uint256 _amountToWithdrawWithDecimal = _getDecimal(_amountToWithdraw);
    
      uint256 amountToRepayinUSD = _repay(_amountToRepayWithDecimal, _zToken,_zTokenUSDRate);

      require(amountToRepayinUSD >= _amountToWithdrawWithDecimal, "Insufficient Collateral");

      /**
      * Substract withdraw from current net mint value and assign new mint value
      */
      uint256 amountToSubtract = (netMintUser[msg.sender] * amountToRepayinUSD/User[msg.sender].userDebtOutstanding);

      netMintUser[msg.sender] -= amountToSubtract;

      netMintGlobal -= amountToSubtract;

    /**
        Adjusted Debt and collaterization ratios are used instead of User debt outstanding and user collateral ratio since we need to factor in amount to repay and amount to withdraw in both equations respectively.
     */
      uint256 AdjustedDebt; 
      uint256 AdjustedCollateralizationRatio;

       /**
        *  Check if Net Mint User and Net Mint Global = 0 
        */
     if (netMintUser[msg.sender] == 0) {
       /**
        * If user has never minted, set Debt = 0
        */
        AdjustedDebt = 0;

     } else {
        
        AdjustedDebt = netMintUser[msg.sender]/netMintGlobal*((IERC20(zUSD).totalSupply() + 
        IERC20(zNGN).totalSupply() / zNGNUSDRate + IERC20(zCFA).totalSupply() / zCFAUSDRate + 
        IERC20(zZAR).totalSupply() / zZARUSDRate) - amountToRepayinUSD);

     }
        
        /** 
        * Update adjusted collateral ratio if Adjusted is more than 0 else go straight to handle repayment and withdraw
        */

        if(AdjustedDebt > 0){
            AdjustedCollateralizationRatio = 10**3 * (User[msg.sender].userCollateralBalance - _amountToWithdrawWithDecimal) / AdjustedDebt;
        }
        

        if(AdjustedCollateralizationRatio >= COLLATERIZATION_RATIO_THRESHOLD || AdjustedDebt == 0) {

          bool burnSuccess = _burn(zUSD, msg.sender, amountToRepayinUSD);

          if(!burnSuccess) revert BurnFailed();

        _updateUserDebtOutstanding(msg.sender, netMintUser[msg.sender], netMintGlobal, zNGNUSDRate, zCFAUSDRate, zZARUSDRate);
        
        if(netMintGlobal > 0){
            User[msg.sender].collaterizationRatio =  10**3 * (User[msg.sender].userCollateralBalance / User[msg.sender].userDebtOutstanding );
        }
        /** 
        * @TODO - Implement actual transfer of cUSD _amountToWithdrawWithDecimal value
        */
        bool transferSuccess = IERC20(collateral).transfer(
            msg.sender,
            _amountToWithdrawWithDecimal
        );

        if(!transferSuccess) revert TransferFailed();
    }
        emit Withdraw(msg.sender, _zToken, _amountToRepay, _amountToWithdraw);
    }

    function liquidate(
        address _user, 
        uint256 zNGNUSDRate, 
        uint256 zCFAUSDRate, 
        uint256 zZARUSDRate
    ) external nonReentrant payable {
        /**
        * Update the user's debt balance with latest price feeds
         */
        _updateUserDebtOutstanding(_user, netMintUser[_user], netMintGlobal, zNGNUSDRate, zCFAUSDRate, zZARUSDRate);

        /**
        * Update user's collateral ratio
         */
        User[_user].collaterizationRatio = (10**3 * User[_user].userCollateralBalance / User[_user].userDebtOutstanding);

        /**
        * User collateral ratio must be lower than healthy threshold for liquidation to occur
         */
        require(User[_user].collaterizationRatio < COLLATERIZATION_RATIO_THRESHOLD, "User has a healthy collateral ratio");

        /**
        * check if the liquidator has sufficient zUSD to repay the debt
        * burn the zUSD
        */
        require(IERC20(zUSD).balanceOf(msg.sender) >= User[_user].userDebtOutstanding, "Liquidator does not have sufficient zUSD to repay debt");

        bool burnSuccess = _burn(zUSD, msg.sender, User[_user].userDebtOutstanding);

        if(!burnSuccess) revert BurnFailed();

        /**
        * Get reward fee
        * Send the equivalent of debt as collateral and also a 10% fee to the liquidator
         */
        uint256 rewardFee = (User[_user].userDebtOutstanding * LIQUIDATION_REWARD) / 100;

        uint256 totalRewards = User[_user].userDebtOutstanding + rewardFee;

        bool transferSuccess = IERC20(collateral).transferFrom(msg.sender, address(this), totalRewards);

        if(!transferSuccess) revert TransferFailed();

        emit Liquidate(_user, User[_user].userDebtOutstanding, totalRewards, msg.sender);

        /**
        * @TODO - netMintGlobal = netMintGlobal - netMintUser, Update users collateral balance by substracting the totalRewards, netMintUser = 0, userDebtOutstanding = 0
         */
    }

    /**
    * Get user balance
    */
    function getBalance(address _token) external view returns(uint256){
        return IERC20(_token).balanceOf(msg.sender);
    }

    /**
     * @dev Returns the minted token value for a particular user
     */
    function getNetUserMintValue(address _address)
        external
        view
        returns (uint256)
    {
        return netMintUser[_address];
    }

    /**
     * @dev Returns the total minted token value
     */
    function getNetGlobalMintValue()
        external
        view
        returns (uint256)
    {
        return netMintGlobal;
    }

    /**
     * Get User struct values
     */
    function getCollaterizationRatio() external view returns (uint256) {
        return User[msg.sender].collaterizationRatio;
    }

/**
* Allow values such as collateral balance and debt outstanding to be updated without propping up wallet(metamask) interaction. This will enable us display these values in realtime to the users.
 */
    function getUserCollateralBalance() external view returns (uint256) {
        return User[msg.sender].userCollateralBalance;
    }

    function getUserDebtOutstanding() external view returns (uint256) {
        return User[msg.sender].userDebtOutstanding;
    }

    /**
     * Add collateral address
     */
    function addCollateralAddress(address _address) external onlyOwner {
        collateral = _address;
    }

    /**
     * Add the four zToken contract addresses
     */
    function addZUSDAddress(address _address) external onlyOwner {
        zUSD = _address;
    }

    function addZNGNAddress(address _address) external onlyOwner {
        zNGN = _address;
    }

    function addZCFAAddress(address _address) external onlyOwner {
        zCFA = _address;
    }

    function addZZARAddress(address _address) external onlyOwner {
        zZAR = _address;
    }

    /**
     * Get Total Supply of zTokens
     */
    function getTotalSupply(address _address) external view returns (uint256) {
        return IERC20(_address).totalSupply();
    }

    /**
    * view minters addresses
    */
    function viewMintersAddress() external view returns (address[] memory) {
        return mintersAddresses;
    }

    /**
     * Private functions
     */
    function _mint(
        address _tokenAddress,
        address _userAddress,
        uint256 _amount
    ) internal virtual returns(bool) {
        ZTokenInterface(_tokenAddress).mint(_userAddress, _amount);

        return true;
    }

    function _burn(
        address _tokenAddress,
        address _userAddress,
        uint256 _amount
    ) internal virtual returns(bool) {
        ZTokenInterface(_tokenAddress).burn(_userAddress, _amount);

        return true;
    }

    /**
     * Allows a user swap back their zTokens to zUSD
     */
    function _repay(
        uint256 _amount,
        address _zToken,
        uint256 _zTokenUsdRate
    ) internal virtual returns (uint256) {
        // require(IERC20(_zToken).balanceOf(msg.sender) >= _amount, "Insufficient balance");
        uint256 zUSDMintAmount;

      /** 
      * Get the amount to mint in zUSD
      */ 
        zUSDMintAmount = _amount * (1/_zTokenUsdRate);

        _burn(_zToken, msg.sender, _amount);

        _mint(zUSD, msg.sender, zUSDMintAmount); 


        return zUSDMintAmount;
    }

    /**
    * Multiply values by 10^18
     */
    function _getDecimal(uint256 amount) internal virtual returns (uint256) {
        uint256 decimalAmount;

        decimalAmount = amount * 10 ** 18;

        return decimalAmount;
    }


    /** 
    * Get User Outstanding Debt
    */
    function _updateUserDebtOutstanding(
        address _address,
        uint256 _netMintUserzUSDValue, 
        uint256 _netMintGlobalzUSDValue, 
        uint256 zNGNUSDRate, 
        uint256 zCFAUSDRate, 
        uint256 zZARUSDRate
    ) internal virtual returns(uint256){

        if(_netMintGlobalzUSDValue > 0 && _netMintUserzUSDValue > 0 ){
            User[_address].userDebtOutstanding = _netMintUserzUSDValue/_netMintGlobalzUSDValue * (IERC20(zUSD).totalSupply() + 
            IERC20(zNGN).totalSupply() / zNGNUSDRate + 
            IERC20(zCFA).totalSupply() / zCFAUSDRate + 
            IERC20(zZAR).totalSupply() / zZARUSDRate);
            
        }else{

            User[_address].userDebtOutstanding = 0;
        }
        
        return User[_address].userDebtOutstanding;
    }

    /**
    * set collaterization ratio threshold
     */
     function setCollaterizationRatioThreshold(uint256 value) external onlyOwner {
        COLLATERIZATION_RATIO_THRESHOLD = value;
     }

    /**
    * set liquidation reward
     */
    function setLiquidationReward(uint256 value) external onlyOwner {
        LIQUIDATION_REWARD = value;
    }

    /**
    * Helper function to test the impact of a transaction i.e mint, burn, deposit or withdrawal by a user
     */
    function _testImpact(address _address, uint256 _zUsdMintAmount, uint256 _zUsdBurnAmount,uint256  _depositAmount, uint256 _withdrawalAmount) internal virtual returns(bool){
        /**
        * Initialize test variables
         */
        uint256 collateralMovement;
        uint256 netMintMovement;
        /**
        * Adjuested Net Mint is initialized from netMintUser[msg.sender]
         */
        uint256 adjustedNetMint = netMintUser[_address];
        /**
        * Global Net Mint is initialized from netMintGlobal
         */
        uint256 globalNetMint = netMintGlobal;

        uint256 collaterizationRatio = COLLATERIZATION_RATIO_THRESHOLD;

        collateralMovement = _depositAmount - _withdrawalAmount + User[_address].userCollateralBalance;

        netMintMovement = _zUsdMintAmount - (netMintUser[_address] * (_zUsdBurnAmount / User[_address].userDebtOutstanding));

        adjustedNetMint += netMintMovement;
        globalNetMint += netMintMovement;

        uint256 debt = (globalNetMint + _zUsdMintAmount - _zUsdBurnAmount) * adjustedNetMint/globalNetMint;
        
        uint256 collateralRatioMultipliedByDebt = debt * collaterizationRatio / 10**3;

        require(collateralMovement >= collateralRatioMultipliedByDebt, "False");

        return true;
    }

    //test function
    // function getUserDebtOutstanding(
    //     uint256 _netMintUserzUSDValue,
    //     uint256 _netMintGlobalzUSDValue,
    //     uint256 totalSupply,
    //     uint256 USDSupply
    // ) external returns (uint256) {
    //     User[msg.sender].userDebtOutstanding =
    //         (_netMintUserzUSDValue / _netMintGlobalzUSDValue) *
    //         (USDSupply +
    //             totalSupply /
    //             zNGNzUSDPair +
    //             totalSupply /
    //             zCFAzUSDPair +
    //             totalSupply /
    //             zZARzUSDPair);
    //     return User[msg.sender].userDebtOutstanding;
    // }
}

