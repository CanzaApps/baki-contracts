// SPDX-License-Identifier: MIT

/**
 * NOTE
 * Always do additions first
 * Check if the substracting value is greater than or less than the added values i.e check for a negative result
 */

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ZTokenInterface.sol";
import "./libraries/WadRayMath.sol";
import "./interfaces/BakiOracleInterface.sol";

error TransferFailed();
error MintFailed();
error BurnFailed();
error ImpactFailed();

contract Vault is ReentrancyGuard, Ownable {
    /**
     * addresses of both the collateral and ztokens
     */
    address private collateral;
    address private zUSD;
    address private zXAF;
    address private zNGN;
    address private zZAR;

    /**
     * exchange rates of 1 USD to zTokens
     * TODO These should be fetched from an Oracle
     */
    address private Oracle;

    constructor() {   
    }

    uint256 private constant USD = 1e3;

    uint256 private constant MULTIPLIER = 1e6;

    uint256 private constant HALF_MULTIPLIER = 1e3;

    uint256 public COLLATERIZATION_RATIO_THRESHOLD = 15 * 1e2;

    uint256 public LIQUIDATION_REWARD = 10;

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

    address public treasuryWallet = 0x6F996Cb36a2CB5f0e73Fc07460f61cD083c63d4b;

    address public mintersWallet = 0x6F996Cb36a2CB5f0e73Fc07460f61cD083c63d4b;

    uint256 public swapFee = WadRayMath.wadDiv(3, 1000);

    uint256 public globalMintersPercentOfSwapFee = WadRayMath.wadDiv(3, 4);

    uint256 public treasuryPercentOfSwapFee = WadRayMath.wadDiv(1, 4);

    /**
     * Store minters addresses as a list
     */
    address[] public mintersAddresses;

    address[] private _blacklistedAddresses;

    bool public transactionsPaused = false;

    /**
    * @dev modifier to check for blacklisted addresses
     */
    modifier blockBlacklistedAddresses() {
        for (uint i = 0; i < _blacklistedAddresses.length; i++) {
            if (msg.sender == _blacklistedAddresses[i]) {
                revert("This address has been blacklisted");
            }
        }
        _;
    }

    modifier isTransactionsPaused() {
        require(transactionsPaused == false, "transactions are paused");
        _;
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

    event AddZUSDAddress(address _address);

    event AddZNGNAddress(address _address);

    event AddZXAFAddress(address _address);

    event AddZZARAddress(address _address);

    event SetCollaterizationRatioThreshold(uint256 _value);

    event SetLiquidationReward(uint256 _value);

    event AddAddressToBlacklist(address _address);

    event RemoveAddressFromBlacklist(address _address);

    event PauseTransactions();

    event AddTreasuryWallet(address _address);

    event AddMintersWallet(address _address);

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
        nonReentrant blockBlacklistedAddresses() isTransactionsPaused()
    {
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

        if (!transferSuccess) revert TransferFailed();

        userCollateralBalance[msg.sender] += _depositAmountWithDecimal;

        /**
         * if this is user's first mint, add to minters list
         */
        if (grossMintUser[msg.sender] == 0) {
            mintersAddresses.push(msg.sender);
        }

        bool mintSuccess = _mint(zUSD, msg.sender, _mintAmountWithDecimal);

        if (!mintSuccess) revert MintFailed();

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
    ) external nonReentrant blockBlacklistedAddresses() isTransactionsPaused() {
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

        swapFeePerTransaction = swapFee * _amountWithDecimal;

        swapFeePerTransaction = swapFeePerTransaction / MULTIPLIER;

        swapFeePerTransactionInUsd = swapFeePerTransaction * HALF_MULTIPLIER;

        swapFeePerTransactionInUsd = swapFeePerTransactionInUsd / _zTokenFromUSDRate;
       
        /**
         * Get the USD values of involved zTokens
         * Handle minting of new tokens and burning of user tokens
         */
        swapAmount = _amountWithDecimal - swapFeePerTransaction;
        mintAmount =
            swapAmount *
            WadRayMath.wadDiv(_zTokenToUSDRate, _zTokenFromUSDRate);
        mintAmount = mintAmount / MULTIPLIER;

        bool burnSuccess = _burn(_zTokenFrom, msg.sender, _amountWithDecimal);

        if (!burnSuccess) revert BurnFailed();

        bool mintSuccess = _mint(_zTokenTo, msg.sender, mintAmount);

        if (!mintSuccess) revert MintFailed();

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
        bool treasuryFeeMint = _mint(zUSD, treasuryWallet, treasuryFeePerTransaction);

        if (!treasuryFeeMint) revert MintFailed();

        /**
         * Send the global minters fee from User to the global minters fee wallet
         */
        bool GlobalMintersFee = _mint(zUSD, address(this), globalMintersFeePerTransaction);

        if (!GlobalMintersFee) revert MintFailed();

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
    ) external nonReentrant blockBlacklistedAddresses() isTransactionsPaused() {
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

        uint256 amountToSubtract = (netMintUser[msg.sender] *
            amountToRepayinUSD) / userDebt;

        netMintUser[msg.sender] -= amountToSubtract;

        netMintGlobal -= amountToSubtract;

        bool burnSuccess = _burn(zUSD, msg.sender, amountToRepayinUSD);

        if (!burnSuccess) revert BurnFailed();

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

        if (!transferSuccess) revert TransferFailed();

        _testImpact();

        emit Withdraw(msg.sender, _zToken, _amountToWithdraw);
    }

    function liquidate(address _user) external nonReentrant blockBlacklistedAddresses() isTransactionsPaused() {
        uint256 userDebt;
        uint256 userCollateralRatio;

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
        require(userDebt > 0, "User has no debt");

        userCollateralRatio =
            1e3 *
            WadRayMath.wadDiv(userCollateralBalance[_user], userDebt);

        userCollateralRatio = userCollateralRatio / MULTIPLIER;
        /**
         * User collateral ratio must be lower than healthy threshold for liquidation to occur
         */
        require(
            userCollateralRatio < COLLATERIZATION_RATIO_THRESHOLD,
            "User has a healthy collateral ratio"
        );

        /**
         * check if the liquidator has sufficient zUSD to repay the debt
         * burn the zUSD
         */
        require(
            IERC20(zUSD).balanceOf(msg.sender) >= userDebt,
            "Liquidator does not have sufficient zUSD to repay debt"
        );

        bool burnSuccess = _burn(zUSD, msg.sender, userDebt);

        if (!burnSuccess) revert BurnFailed();

        // _testImpact(zNGNUSDRate, zXAFUSDRate, zZARUSDRate);

        /**
         * Get reward fee
         * Send the equivalent of debt as collateral and also a 10% fee to the liquidator
         */
        uint256 rewardFee = (userDebt * LIQUIDATION_REWARD) / 100;

        uint256 totalRewards = userDebt + rewardFee;

        netMintGlobal = netMintGlobal - netMintUser[_user];

        netMintUser[_user] = 0;

         /**
         * Possible overflow
         */
        if (userCollateralBalance[_user] >= totalRewards) {
            userCollateralBalance[_user] =
                userCollateralBalance[_user] -
                totalRewards;
        } else {
            userCollateralBalance[_user] = 0;
        }

        bool transferSuccess = IERC20(collateral).transfer(
            msg.sender,
            totalRewards
        );

        if (!transferSuccess) revert TransferFailed();

        emit Liquidate(_user, userDebt, totalRewards, msg.sender);

        /**
         * @TODO - netMintGlobal = netMintGlobal - netMintUser, Update users collateral balance by substracting the totalRewards, netMintUser = 0, userDebtOutstanding = 0
         */
    }

    /**
     * Allow minters to claim rewards/fees on swap
     */
    function claimFees() external nonReentrant {
        require(
            userAccruedFeeBalance[msg.sender] > 0,
            "User has no accumulated rewards"
        );

        bool transferSuccess = IERC20(zUSD).transfer(
            msg.sender,
            userAccruedFeeBalance[msg.sender]
        );
        if (!transferSuccess) revert TransferFailed();

        userAccruedFeeBalance[msg.sender] = 0;
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

    function getUserCollateralBalance() external view returns (uint256) {
        return userCollateralBalance[msg.sender];
    }

    /**
     * Add collateral address
     */
    function addCollateralAddress(address _address) external onlyOwner {
        require(_address != address(0), "address cannot be a zero address");

        collateral = _address;

        emit AddCollateralAddress(_address);
    }

    /**
     * Add the four zToken contract addresses
     */
    function addZUSDAddress(address _address) external onlyOwner {
        require(_address != address(0), "address cannot be a zero address");

        zUSD = _address;

        emit AddZUSDAddress(_address);
    }

    function addZNGNAddress(address _address) external onlyOwner {
        require(_address != address(0), "address cannot be a zero address");

        zNGN = _address;

        emit AddZNGNAddress(_address);
    }

    function addZXAFAddress(address _address) external onlyOwner {
        require(_address != address(0), "address cannot be a zero address");

        zXAF = _address;

        emit AddZXAFAddress(_address);
    }

    function addZZARAddress(address _address) external onlyOwner {
        require(_address != address(0), "address cannot be a zero address");

        zZAR = _address;

        emit AddZZARAddress(_address);
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
        require(_address != address(0), "address cannot be a zero address");

        _blacklistedAddresses.push(_address);

        emit AddAddressToBlacklist(_address);
    }

    /**
    * Check for blacklisted address
     */
    function checkForBlacklistedAddress(address _address) public view returns(bool) {
         for(uint256 i = 0; i < _blacklistedAddresses.length - 1; i++){

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
        require(_address != address(0), "address cannot be a zero address");

        bool isAddressBlacklisted = checkForBlacklistedAddress(_address);
        
        require(isAddressBlacklisted == true, "address is not a blacklisted address");

        uint256 index;

        for(uint256 i = 0; i < _blacklistedAddresses.length - 1; i++){

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

    function addMintersWallet(address _address) external onlyOwner {
        require(_address != address(0), "address cannot be a zero address");

        mintersWallet = _address;

        emit AddMintersWallet(_address);
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
    ) internal returns (bool) {
        bool success = ZTokenInterface(_tokenAddress).mint(_userAddress, _amount);

        return success;
    }

    function _burn(
        address _tokenAddress,
        address _userAddress,
        uint256 _amount
    ) internal returns (bool) {
        bool success = ZTokenInterface(_tokenAddress).burn(_userAddress, _amount);

        return success;
    }

    /**
     * Allows a user swap back their zTokens to zUSD
     */
    function _repay(uint256 _amount, address _zToken)
        internal
        returns (uint256)
    {
        // require(IERC20(_zToken).balanceOf(msg.sender) >= _amount, "Insufficient balance");
        uint256 zUSDMintAmount;

        /**
         * Get the amount to mint in zUSD
         */
        uint256 zTokenUSDRate = getZTokenUSDRate(_zToken);

        zUSDMintAmount = _amount * 1 * HALF_MULTIPLIER;

        zUSDMintAmount = zUSDMintAmount / zTokenUSDRate;

        bool burnSuccess = _burn(_zToken, msg.sender, _amount);

        if(!burnSuccess) revert BurnFailed();

        bool mintSuccess = _mint(zUSD, msg.sender, zUSDMintAmount);

        if(!mintSuccess) revert MintFailed();

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
            revert("Invalid address");
        }

        return zTokenUSDRate;
    }

    /**
     * Get User Outstanding Debt
     */

    function _updateUserDebtOutstanding(
        uint256 _netMintUserzUSDValue,
        uint256 _netMintGlobalzUSDValue
    ) public view returns (uint256) {
        require(
            _netMintGlobalzUSDValue > 0,
            "Global zUSD mint too low, underflow may occur"
        );
        uint256 globalDebt;
        uint256 userDebtOutstanding;
        uint256 mintRatio;

        globalDebt =
            (IERC20(zUSD).totalSupply() * HALF_MULTIPLIER) +
            WadRayMath.wadDiv(IERC20(zNGN).totalSupply(), BakiOracleInterface(Oracle).NGNUSD()) +
            WadRayMath.wadDiv(IERC20(zXAF).totalSupply(), BakiOracleInterface(Oracle).XAFUSD()) +
            WadRayMath.wadDiv(IERC20(zZAR).totalSupply(), BakiOracleInterface(Oracle).ZARUSD());

        // globalDebt = globalDebt / HALF_MULTIPLIER;

        mintRatio = WadRayMath.wadDiv(
            _netMintUserzUSDValue,
            _netMintGlobalzUSDValue
        );

        userDebtOutstanding = mintRatio * globalDebt;

        uint256 tempMultiplier = MULTIPLIER * HALF_MULTIPLIER;

        userDebtOutstanding = userDebtOutstanding / tempMultiplier;

        return userDebtOutstanding;
    }

    /**
     * Helper function to test the impact of a transaction i.e mint, burn, deposit or withdrawal by a user
     */
    function _testImpact() internal view returns (bool) {
        uint256 userDebt;
        /**
         * If the netMintGlobal is 0, then
         */
        if (netMintGlobal != 0) {
            require(
                netMintGlobal > 0,
                "Global zUSD mint too low, underflow may occur"
            );

            userDebt = _updateUserDebtOutstanding(
                netMintUser[msg.sender],
                netMintGlobal
            );

            uint256 collateralRatioMultipliedByDebt = (userDebt *
                COLLATERIZATION_RATIO_THRESHOLD) / 1e3;

            require(
                userCollateralBalance[msg.sender] >=
                    collateralRatioMultipliedByDebt,
                "User does not have sufficient collateral to cover this transaction"
            );
        }
        return true;
    }
}
