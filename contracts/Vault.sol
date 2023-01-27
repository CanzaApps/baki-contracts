// SPDX-License-Identifier: MIT

/**
 * NOTE
 * Always do additions first
 * Check if the substracting value is greater than or less than the added values i.e check for a negative result
 */

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ZTokenInterface.sol";
import "./libraries/WadRayMath.sol";
import "./interfaces/BakiOracleInterface.sol";

error TransferFailed();
error MintFailed();
error BurnFailed();
error ImpactFailed();

contract Vault is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    /**
     * addresses of both the collateral and ztokens
     */
    address private collateral;
    address private zUSD;
    address private zXAF;
    address private zNGN;
    address private zZAR;

    address private Oracle;

    uint256 private constant USD = 1e3;

    uint256 private constant MULTIPLIER = 1e6;

    uint256 private constant HALF_MULTIPLIER = 1e3;

    uint256 public COLLATERIZATION_RATIO_THRESHOLD;

    uint256 public LIQUIDATION_REWARD;

    /**
     * Net User Mint
     * Maps user address => cumulative mint value
     */
    mapping(address => uint256) public netMintUser;

    mapping(address => uint256) private grossMintUser;

    mapping(address => uint256) public userCollateralBalance;

    /**
     * Net Global Mint
     */
    uint256 public netMintGlobal;
    /**
     * map users to accrued fee balance
     * store 75% swap fee to be shared by minters
     * store 25% swap fee separately
     * user => uint256
     */

    mapping(address => uint256) public userAccruedFeeBalance;

    mapping(address => uint256) private mintersRewardPerTransaction;

    uint256 public globalMintersFee;

    address public treasuryWallet;

    uint256 public swapFee;

    uint256 public globalMintersPercentOfSwapFee;

    uint256 public treasuryPercentOfSwapFee;

    /**
     * Store minters addresses as a list
     */
    address[] public mintersAddresses;

    address[] public _blacklistedAddresses;

    bool public transactionsPaused;

    address[] public usersInLiquidationZone;

    uint256 public totalCollateral;

    uint256 private swapAmountInUSD;

    uint256 public totalSwapVolume;
       /**
    * Initializers
     */

    function vault_init(
        address _zUSD, 
        address _zNGN, 
        address _zXAF, 
        address _zZAR,
        address _oracle,
        address _collateral
        ) external onlyOwner initializer {
        COLLATERIZATION_RATIO_THRESHOLD = 15 * 1e2;
        LIQUIDATION_REWARD = 15;
        treasuryWallet = 0x6F996Cb36a2CB5f0e73Fc07460f61cD083c63d4b;
        swapFee = WadRayMath.wadDiv(12, 1000);
        globalMintersPercentOfSwapFee = WadRayMath.wadDiv(3, 4);
        treasuryPercentOfSwapFee = WadRayMath.wadDiv(1, 4);
        transactionsPaused = false;
        zUSD = _zUSD;
        zNGN = _zNGN;
        zXAF = _zXAF;
        zZAR = _zZAR;
        Oracle = _oracle;
        collateral = _collateral;

        __Ownable_init();
    }

    /**
    * @dev 
     */

    event Deposit(
        address indexed _account,
        address indexed _token,
        uint256 _depositAmount,
        uint256 _mintAmount
    );
    event Swap(
        address indexed _account,
        address indexed _zTokenFrom,
        address indexed _zTokenTo
    );
    event Withdraw(
        address indexed _account,
        address indexed _token,
        uint256 indexed _amountToWithdraw
    );
    event Liquidate(
        address indexed _account,
        uint256 indexed debt,
        uint256 indexed rewards,
        address liquidator
    );

    event AddCollateralAddress(address _address);

    event SetCollaterizationRatioThreshold(uint256 _value);

    event SetLiquidationReward(uint256 _value);

    event AddAddressToBlacklist(address _address);

    event RemoveAddressFromBlacklist(address _address);

    event PauseTransactions();

    event AddTreasuryWallet(address _address);

    event ChangeSwapFee(uint256 a, uint256 b);

    event ChangeGlobalMintersFee(uint256 a, uint256 b);

    event ChangeTreasuryFee(uint256 a, uint256 b);

    event SetOracleAddress(address _address);

    /** 
    @notice Allows a user to deposit cUSD collateral in exchange for some amount of zUSD.
     _depositAmount  The amount of cUSD the user sent in the transaction
     */
    function depositAndMint(uint256 _depositAmount, uint256 _mintAmount)
        external
        nonReentrant
    {
        blockBlacklistedAddresses();
        isTransactionsPaused();
        uint256 _depositAmountWithDecimal = _getDecimal(_depositAmount);
        uint256 _mintAmountWithDecimal = _getDecimal(_mintAmount);

        require(
            IERC20(collateral).balanceOf(msg.sender) >=
                _depositAmountWithDecimal,
            "Insufficient balance"
        );

        // transfer cUSD tokens from user wallet to vault contract
        bool transferSuccess = IERC20(collateral).transferFrom(
            msg.sender,
            address(this),
            _depositAmountWithDecimal
        );

        if (!transferSuccess) revert();

        userCollateralBalance[msg.sender] += _depositAmountWithDecimal;

        totalCollateral += _depositAmountWithDecimal;
        /**
         * if this is user's first mint, add to minters list
         */
        if (grossMintUser[msg.sender] == 0) {
            mintersAddresses.push(msg.sender);
        }

        _mint(zUSD, msg.sender, _mintAmountWithDecimal);

        netMintUser[msg.sender] += _mintAmountWithDecimal;
        grossMintUser[msg.sender] += _mintAmountWithDecimal;

        netMintGlobal += _mintAmountWithDecimal;

        /**
         * Update user outstanding debt after successful mint
         * Check the impact of the mint
         */
        _testImpact();

        emit Deposit(msg.sender, collateral, _depositAmount, _mintAmount);
    }

    /**
     * Allows a user to swap zUSD for other zTokens using their exchange rates
     */
    function swap(
        uint256 _amount,
        address _zTokenFrom,
        address _zTokenTo
    ) external nonReentrant {
        blockBlacklistedAddresses();
        isTransactionsPaused();

        uint256 _amountWithDecimal = _getDecimal(_amount);
        uint256 swapFeePerTransactionInUsd;
        uint256 swapAmount;
        uint256 mintAmount;
        uint256 swapFeePerTransaction;
        uint256 globalMintersFeePerTransaction;
        uint256 treasuryFeePerTransaction;

        require(
            IERC20(_zTokenFrom).balanceOf(msg.sender) >= _amountWithDecimal,
            "Insufficient balance"
        );
        uint256 _zTokenFromUSDRate = getZTokenUSDRate(_zTokenFrom);
        uint256 _zTokenToUSDRate = getZTokenUSDRate(_zTokenTo);
       
        /**
         * Get the USD values of involved zTokens
         * Handle minting of new tokens and burning of user tokens
         */
        swapAmount = (_amountWithDecimal * _zTokenToUSDRate);

        swapAmount = swapAmount / _zTokenFromUSDRate;

        swapFeePerTransaction = swapFee * swapAmount;

        swapFeePerTransaction = swapFeePerTransaction / MULTIPLIER;

        swapFeePerTransactionInUsd = swapFeePerTransaction * HALF_MULTIPLIER;

        swapFeePerTransactionInUsd = swapFeePerTransactionInUsd / _zTokenToUSDRate;

        mintAmount = swapAmount - swapFeePerTransaction;

        /**
         * Track the USD value of the swap amount
         */
        swapAmountInUSD = _amountWithDecimal * MULTIPLIER;
        swapAmountInUSD = _amountWithDecimal / _zTokenFromUSDRate;

        totalSwapVolume += swapAmountInUSD; 

        _burn(_zTokenFrom, msg.sender, _amountWithDecimal);

        _mint(_zTokenTo, msg.sender, mintAmount);

        /**
         * Handle swap fees and rewards
         */
        globalMintersFeePerTransaction =
            globalMintersPercentOfSwapFee * swapFeePerTransactionInUsd;

        globalMintersFeePerTransaction = globalMintersFeePerTransaction / MULTIPLIER;

        globalMintersFee += globalMintersFeePerTransaction;

        treasuryFeePerTransaction =
            treasuryPercentOfSwapFee * swapFeePerTransactionInUsd;

        treasuryFeePerTransaction = treasuryFeePerTransaction / MULTIPLIER;

        /**
         * Send the treasury amount to a treasury wallet
         */
        _mint(zUSD, treasuryWallet, treasuryFeePerTransaction);

        /**
         * Send the global minters fee from User to the global minters fee wallet
         */
        _mint(zUSD, address(this), globalMintersFeePerTransaction);

        for (uint256 i = 0; i < mintersAddresses.length; i++) {
            mintersRewardPerTransaction[mintersAddresses[i]] =
                ((netMintUser[mintersAddresses[i]] * MULTIPLIER) /
                    netMintGlobal) *
                globalMintersFeePerTransaction;

            userAccruedFeeBalance[mintersAddresses[i]] +=
                mintersRewardPerTransaction[mintersAddresses[i]] /
                MULTIPLIER;
        }
        emit Swap(msg.sender, _zTokenFrom, _zTokenTo);
    }

    /**
     * Allows to user to repay and/or withdraw their collateral
     */
    function repayAndWithdraw(
        uint256 _amountToRepay,
        uint256 _amountToWithdraw,
        address _zToken
    ) external nonReentrant {
        blockBlacklistedAddresses();
        isTransactionsPaused();

        uint256 _amountToRepayWithDecimal = _getDecimal(_amountToRepay);
        uint256 _amountToWithdrawWithDecimal = _getDecimal(_amountToWithdraw);

        uint256 amountToRepayinUSD = _repay(_amountToRepayWithDecimal, _zToken);

        uint256 userDebt;

        userDebt = _updateUserDebtOutstanding(
            netMintUser[msg.sender],
            netMintGlobal
        );

        require(
            userCollateralBalance[msg.sender] >= _amountToWithdrawWithDecimal,
            "Insufficient Collateral"
        );

        require(
            userDebt >= amountToRepayinUSD,
            "Amount to repay greater than Debt"
        );

        /**
         * Substract withdraw from current net mint value and assign new mint value
         */

         if(userDebt != 0) {
            uint256 amountToSubtract = (netMintUser[msg.sender] *
            amountToRepayinUSD) / userDebt;

            netMintUser[msg.sender] -= amountToSubtract;

            netMintGlobal -= amountToSubtract;
        }

        _burn(zUSD, msg.sender, amountToRepayinUSD);

        /**
         * Test impact after burn
         */
        /**
         * @TODO - Implement actual transfer of cUSD _amountToWithdrawWithDecimal value
         */
        userCollateralBalance[msg.sender] -= _amountToWithdrawWithDecimal;

        bool transferSuccess = IERC20(collateral).transfer(
            msg.sender,
            _amountToWithdrawWithDecimal
        );

        if (!transferSuccess) revert();

        _testImpact();

        emit Withdraw(msg.sender, _zToken, _amountToWithdraw);
    }

    function liquidate(address _user) external nonReentrant {
        blockBlacklistedAddresses();
        isTransactionsPaused();

         uint256 userDebt;
        
        bool isUserInLiquidationZone = checkUserForLiquidation(_user);
        require(isUserInLiquidationZone == true, "User is not in the liquidation zone");

        uint totalRewards = getPotentialTotalReward(_user);

        /**
         * Update the user's debt balance with latest price feeds
         */
        userDebt = _updateUserDebtOutstanding(
            netMintUser[_user],
            netMintGlobal
        );

        /**
         * check if the liquidator has sufficient zUSD to repay the debt
         * burn the zUSD
         */
        require(
            IERC20(zUSD).balanceOf(msg.sender) >= userDebt,
            "Liquidator does not have sufficient zUSD to repay debt"
        );
       
        /**
         * Get reward fee
         * Send the equivalent of debt as collateral and also a 10% fee to the liquidator
         */
        netMintGlobal = netMintGlobal - netMintUser[_user];
        netMintUser[_user] = 0;

        _burn(zUSD, msg.sender, userDebt);

         /**
         * Send total rewards to Liquidator
         */
        if (userCollateralBalance[_user] <= totalRewards) {

            userCollateralBalance[_user] = 0;

            bool transferSuccess = IERC20(collateral).transfer(
            msg.sender,
            totalRewards
                );

            if (!transferSuccess) revert();

        } else {
            
            userCollateralBalance[_user] -= totalRewards;

            bool transferSuccess = IERC20(collateral).transfer(
            msg.sender,
            totalRewards
            );

            if (!transferSuccess) revert();

        }

        emit Liquidate(_user, userDebt, totalRewards, msg.sender);
    }

    /**
     * Allow minters to claim rewards/fees on swap
     */
    function claimFees() external nonReentrant {
        require(
            userAccruedFeeBalance[msg.sender] > 0,
            "User has no accumulated rewards"
        );
        uint256 amount;

        amount = userAccruedFeeBalance[msg.sender];
        userAccruedFeeBalance[msg.sender] = 0;

        bool transferSuccess = IERC20(zUSD).transfer(
            msg.sender,
            amount
        );
        if (!transferSuccess) revert();

    }

    /**
     * Get potential total rewards from user in liquidation zone
     */
    function getPotentialTotalReward(address _user) public view returns (uint256) {
      
        bool isUserInLiquidationZone = checkUserForLiquidation(_user);

        uint256 rate = BakiOracleInterface(Oracle).collateralUSD();

        uint256 _userDebt = _updateUserDebtOutstanding(
            netMintUser[_user],
            netMintGlobal
        );

        require(isUserInLiquidationZone == true, "User is not in the liquidation zone");
        require(_userDebt > 0, "User has no debt");

        uint256 rewardFee = (_userDebt * LIQUIDATION_REWARD) / 100;

        uint256 rewards = _userDebt + rewardFee;

        rewards = rewards * HALF_MULTIPLIER;

        rewards = rewards / rate;

         if (userCollateralBalance[_user] <= rewards) {

            return userCollateralBalance[_user];

        } else {
            
            return rewards;

        }
    }

    /**
     * Adds and removes users in Liquidation zone
     */
    function manageUsersInLiquidationZone() external onlyOwner returns (address[] memory) {
        
        for(uint256 i = 0; i < mintersAddresses.length; i++) {
            bool isUserInLiquidationZone = checkUserForLiquidation(mintersAddresses[i]);
            bool isUserAlreadyInLiquidationArray = _checkIfUserAlreadyExistsInLiquidationList(mintersAddresses[i]);

            // If a user is in liquidation zone and not in the liquidation list, add user to the list
            if (isUserInLiquidationZone == true && isUserAlreadyInLiquidationArray == false){
                usersInLiquidationZone.push(mintersAddresses[i]);
            }
            
            // If the user is not/ no longer in the liquidation zone but still in the list, remove from the list
            if (isUserInLiquidationZone == false && isUserAlreadyInLiquidationArray == true){
                _removeUserFromLiquidationList(mintersAddresses[i]);
            }
        }
        return usersInLiquidationZone;
    }

    function getUserFromLiquidationZone() external view returns (address[] memory) {
        return usersInLiquidationZone;
    }

    /**
     * Helper function to check that a user is already present in liquidation list
     */
    function _checkIfUserAlreadyExistsInLiquidationList(address _user) internal view returns (bool) {
         
        for(uint256 i = 0; i < usersInLiquidationZone.length; i++) {
            if(usersInLiquidationZone[i] == _user) {
                return true;
            }
        }
        return false;
    }

    /**
     * Helper function to remove a user from the liquidation list
     */
    function _removeUserFromLiquidationList(address _user) internal onlyOwner {
         
         bool isUserAlreadyInLiquidationArray = _checkIfUserAlreadyExistsInLiquidationList(_user);

         require(isUserAlreadyInLiquidationArray == true, "user is not in the liquidation zone");

         uint256 index;

         for(uint256 i = 0; i < usersInLiquidationZone.length; i++){
            if(usersInLiquidationZone[i] == _user){
                index = i;
            }
         }

         usersInLiquidationZone[index] = usersInLiquidationZone[usersInLiquidationZone.length - 1];

         usersInLiquidationZone.pop();
    }

    /**
     * Check User for liquidation
     */
    function checkUserForLiquidation(address _user) public view returns (bool) {
        require(_user != address(0), "address cannot be a zero address");

        uint256 userDebt;
        uint256 userCollateralRatio;

    /**
     * Get the USD value of the user's collateral
     */
        uint256 USDValueOfCollateral = getUSDValueOfCollateral(userCollateralBalance[_user]);        

        /**
         * Update the user's debt balance with latest price feeds
         */
        userDebt = _updateUserDebtOutstanding(
            netMintUser[_user],
            netMintGlobal
        );

        /**
         * Ensure user has debt before progressing
         * Update user's collateral ratio
         */
        
        if (userDebt != 0) {
            userCollateralRatio =
                1e3 *
                WadRayMath.wadDiv(USDValueOfCollateral, userDebt);

            userCollateralRatio = userCollateralRatio / MULTIPLIER;

            if (userCollateralRatio < COLLATERIZATION_RATIO_THRESHOLD){
                return true;
            }
        }

        return false;
    }

    /**
     * Get user balance
     */
    function getBalance(address _token) external view returns (uint256) {
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
    function getNetGlobalMintValue() external view returns (uint256) {
        return netMintGlobal;
    }

    /**
    * Get Collateral value in USD
     */
    function getUserCollateralBalance() external view returns (uint256) {
        return userCollateralBalance[msg.sender];
    }

    /**
     * set collaterization ratio threshold
     */
    function setCollaterizationRatioThreshold(uint256 _value)
        external
        onlyOwner
    {
    // Set an upper and lower bound on the new value of collaterization ratio threshold
        require(_value > 12 * 1e2 || _value < 20 * 1e2, "value must be within the set limit");

        COLLATERIZATION_RATIO_THRESHOLD = _value;

        emit SetCollaterizationRatioThreshold(_value);
    }

    /**
     * set liquidation reward
     */
    function setLiquidationReward(uint256 _value) external onlyOwner {
        LIQUIDATION_REWARD = _value;

        emit SetLiquidationReward(_value);
    }

    /**
    * Add to blacklist
     */
    function addAddressToBlacklist(address _address) external onlyOwner {
       
         bool isAddressBlacklisted = checkForBlacklistedAddress(_address);
        
        require(isAddressBlacklisted == false, "address is already a blacklisted address");

        _blacklistedAddresses.push(_address);

        emit AddAddressToBlacklist(_address);
    }

    /**
    * Get blacklisted addresses
     */
    function getBlacklistedAddresses() public view returns(address[] memory) {
        return _blacklistedAddresses;
    }

    /**
    * Check for blacklisted address
     */
    function checkForBlacklistedAddress(address _address) public view returns(bool) {
         for(uint256 i = 0; i < _blacklistedAddresses.length; i++){

            if(_blacklistedAddresses[i] == _address){

                return true;
            }
        }
        return false;
    }

    /**
    * Remove from blacklist
     */
    function removeAddressFromBlacklist(address _address) external onlyOwner {
    
        bool isAddressBlacklisted = checkForBlacklistedAddress(_address);
        
        require(isAddressBlacklisted == true, "not blacklisted address");

        uint256 index;

        for(uint256 i = 0; i < _blacklistedAddresses.length; i++){
            if(_blacklistedAddresses[i] == _address){
                index = i;
            }
        }

        _blacklistedAddresses[index] = _blacklistedAddresses[_blacklistedAddresses.length - 1];

        _blacklistedAddresses.pop();

        emit RemoveAddressFromBlacklist(_address);
    }

    /**
    * Pause transactions
     */
    function pauseTransactions() external onlyOwner { 
    if (transactionsPaused == false) 
        { transactionsPaused = true; }
    else { transactionsPaused = false; }

    emit PauseTransactions();
    }

    /**
     * Change swap variables
     */
    function addTreasuryWallet(address _address) external onlyOwner {
        require(_address != address(0), "address cannot be a zero address");

        treasuryWallet = _address;

        emit AddTreasuryWallet(_address);
    }

    function changeSwapFee(uint256 a, uint256 b)
        external
        onlyOwner
    {
        swapFee = WadRayMath.wadDiv(a, b);

        emit ChangeSwapFee(a,b);
    }

    function changeGlobalMintersFee(uint256 a, uint256 b)
        external
        onlyOwner
    {
        globalMintersPercentOfSwapFee = WadRayMath.wadDiv(
            a,
            b
        );

        emit ChangeGlobalMintersFee(a,b);
    }

    function changeTreasuryFee(uint256 a, uint256 b)
        external
        onlyOwner
    {
        treasuryPercentOfSwapFee = WadRayMath.wadDiv(a, b);

        emit ChangeTreasuryFee(a,b);
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
    ) internal {
        bool success = ZTokenInterface(_tokenAddress).mint(_userAddress, _amount);

        if(!success) revert MintFailed();
    }

    function _burn(
        address _tokenAddress,
        address _userAddress,
        uint256 _amount
    ) internal {
        bool success = ZTokenInterface(_tokenAddress).burn(_userAddress, _amount);

        if(!success) revert BurnFailed();
    }

    /**
     * Allows a user swap back their zTokens to zUSD
     */
    function _repay(uint256 _amount, address _zToken)
        internal
        returns (uint256)
    {
        // require(IERC20(_zToken).balanceOf(msg.sender) >= _amount, "Insufficient balance");
        uint256 zUSDMintAmount = _amount;
        uint256 swapFeePerTransactionInUsd;
        uint256 swapFeePerTransaction;
        uint256 globalMintersFeePerTransaction;
        uint256 treasuryFeePerTransaction;

        /**
        * If the token to be repayed is zUSD, skip the fees, mint, burn process and return the _amount directly
        */
        if (_zToken != zUSD) {
       
        uint256 zTokenUSDRate = getZTokenUSDRate(_zToken);

        /**
        * Get the swap fee per transaction in USD
        */
        
        swapFeePerTransaction = swapFee * _amount;

        swapFeePerTransaction = swapFeePerTransaction / MULTIPLIER;

        swapFeePerTransactionInUsd = swapFeePerTransaction * HALF_MULTIPLIER;

        swapFeePerTransactionInUsd = swapFeePerTransactionInUsd / zTokenUSDRate;  

        /**
        * Get the amount to mint in zUSD
        */
        zUSDMintAmount = _amount - swapFeePerTransaction;
        
        zUSDMintAmount = zUSDMintAmount * 1 * HALF_MULTIPLIER;

        zUSDMintAmount = zUSDMintAmount / zTokenUSDRate;

        _burn(_zToken, msg.sender, _amount);

        _mint(zUSD, msg.sender, zUSDMintAmount);
         /**
         * Handle swap fees and rewards
         */
        globalMintersFeePerTransaction =
            globalMintersPercentOfSwapFee * swapFeePerTransactionInUsd;

        globalMintersFeePerTransaction = globalMintersFeePerTransaction / MULTIPLIER;

        globalMintersFee += globalMintersFeePerTransaction;

        treasuryFeePerTransaction =
            treasuryPercentOfSwapFee * swapFeePerTransactionInUsd;

        treasuryFeePerTransaction = treasuryFeePerTransaction / MULTIPLIER;

         /**
         * Send the treasury amount to a treasury wallet
         */
        _mint(zUSD, treasuryWallet, treasuryFeePerTransaction);
        /**
         * Send the global minters fee from User to the global minters fee wallet
         */
        _mint(zUSD, address(this), globalMintersFeePerTransaction);

        for (uint256 i = 0; i < mintersAddresses.length; i++) {
            mintersRewardPerTransaction[mintersAddresses[i]] =
                ((netMintUser[mintersAddresses[i]] * MULTIPLIER) /
                    netMintGlobal) *
                globalMintersFeePerTransaction;

            userAccruedFeeBalance[mintersAddresses[i]] +=
                mintersRewardPerTransaction[mintersAddresses[i]] /
                MULTIPLIER;

        }
        }

        return zUSDMintAmount;
    }

    /**
     * Multiply values by 10^18
     */
    function _getDecimal(uint256 amount) internal virtual returns (uint256) {
        uint256 decimalAmount;

        decimalAmount = amount * 1e18;

        return decimalAmount;
    }

    /**
    * Set Oracle contract address
     */
    function setOracleAddress(address _address) public onlyOwner {
        require(_address != address(0), "address cannot be a zero address");

        Oracle = _address;

        emit SetOracleAddress(_address);
    }

    /**
    * Returns the USD value of user's collateral
     */
    function getUSDValueOfCollateral(uint256 _amount) public view returns (uint256) {
        uint256 USDValue;
        uint256 rate;
    
        rate = BakiOracleInterface(Oracle).collateralUSD();

        USDValue = _amount * rate;
        USDValue = USDValue / HALF_MULTIPLIER;
        return USDValue;
    }

    /**
     * Returns the appropriate USD exchange rate during a swap/repay
     */
    function getZTokenUSDRate(address _address)
        internal
        virtual
        returns (uint256)
    {
        uint256 zTokenUSDRate;

        if (_address == zNGN) {
            zTokenUSDRate = BakiOracleInterface(Oracle).NGNUSD();
        } else if (_address == zXAF) {
            zTokenUSDRate = BakiOracleInterface(Oracle).XAFUSD();
        } else if (_address == zZAR) {
            zTokenUSDRate = BakiOracleInterface(Oracle).ZARUSD();
        } else if (_address == zUSD) {
            zTokenUSDRate = USD;
        } else {
            revert("Invalid");
        }

        return zTokenUSDRate;
    }

    /**
     * Get Global Debt
     */
    function getGlobalDebt() public view returns(uint256){
         uint256 globalDebt =
            (IERC20(zUSD).totalSupply() * HALF_MULTIPLIER) +
            WadRayMath.wadDiv(IERC20(zNGN).totalSupply(), BakiOracleInterface(Oracle).NGNUSD()) +
            WadRayMath.wadDiv(IERC20(zXAF).totalSupply(), BakiOracleInterface(Oracle).XAFUSD()) +
            WadRayMath.wadDiv(IERC20(zZAR).totalSupply(), BakiOracleInterface(Oracle).ZARUSD());

        return globalDebt;
     }

    /**
     * Get User Outstanding Debt
     */

    function _updateUserDebtOutstanding(
        uint256 _netMintUserzUSDValue,
        uint256 _netMintGlobalzUSDValue
    ) public view returns (uint256) {
       
        if(_netMintGlobalzUSDValue != 0 ) {
            uint256 globalDebt = getGlobalDebt();
            uint256 userDebtOutstanding;
            uint256 mintRatio;

            mintRatio = WadRayMath.wadDiv(
                _netMintUserzUSDValue,
                _netMintGlobalzUSDValue
            );

            userDebtOutstanding = mintRatio * globalDebt;

            uint256 tempMultiplier = MULTIPLIER * HALF_MULTIPLIER;

            userDebtOutstanding = userDebtOutstanding / tempMultiplier;

            return userDebtOutstanding;
        }
     return 0;
    }

       /**
    * @dev modifier to check for blacklisted addresses
     */
    function blockBlacklistedAddresses() internal view {
        for (uint i = 0; i < _blacklistedAddresses.length; i++) {
            if (msg.sender == _blacklistedAddresses[i]) {
                revert("address blacklisted");
            }
        }
    }

    function isTransactionsPaused() internal view {
        require(transactionsPaused == false, "transactions are paused");
    }

    /**
     * Helper function to test the impact of a transaction i.e mint, burn, deposit or withdrawal by a user
     */
    function _testImpact() internal view returns (bool) {
        uint256 userDebt;
        uint256 USDValueOfCollateral;
        
        USDValueOfCollateral = getUSDValueOfCollateral(userCollateralBalance[msg.sender]);
        
        /**
         * If the netMintGlobal is 0, then debt doesn't exist
         */
        if (netMintGlobal != 0) {
            userDebt = _updateUserDebtOutstanding(
                netMintUser[msg.sender],
                netMintGlobal
            );

            uint256 collateralRatioMultipliedByDebt = (userDebt *
                COLLATERIZATION_RATIO_THRESHOLD) / 1e3;

            require(
                USDValueOfCollateral >= collateralRatioMultipliedByDebt,
                "Insufficient collateral"
            );
        }

        return true;
    }
}

