// SPDX-License-Identifier: MIT

/**
 * NOTE
 * Always do additions first
 * Check if the substracting value is greater than or less than the added values i.e check for a negative result
 */

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ZTokenInterface.sol";
import "./libraries/WadRayMath.sol";

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
    address private zCFA;
    address private zNGN;
    address private zZAR;

    /**
     * exchange rates of 1 USD to zTokens
     * TODO These should be fetched from an Oracle
     */

    constructor() {}

    uint256 private constant MULTIPLIER = 1e6;

    uint256 public COLLATERIZATION_RATIO_THRESHOLD = 15 * 1e2;

    uint256 public LIQUIDATION_REWARD = 10;

    /**
     * Net User Mint
     * Maps user address => cumulative mint value
     */
    mapping(address => uint256) private netMintUser;

    mapping(address => uint256) private grossMintUser;

    mapping(address => uint256) public userCollateralBalance;

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
    ) external nonReentrant {
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
        userCollateralBalance[msg.sender] -= _mintAmountWithDecimal;

        netMintGlobal += _mintAmountWithDecimal;

        /**
         * Update user outstanding debt after successful mint
         * Check the impact of the mint
         */
        _testImpact(zNGNUSDRate, zCFAUSDRate, zZARUSDRate);

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

        swapFeePerTransaction = (swapFee * _amountWithDecimal) / MULTIPLIER;
        swapFeePerTransactionInUsd = swapFeePerTransaction / _zTokenFromUSDRate;

        /**
         * Get the USD values of involved zTokens
         * Handle minting of new tokens and burning of user tokens
         */
        swapAmount = _amountWithDecimal - swapFeePerTransaction;
        mintAmount =
            swapAmount *
            ((_zTokenToUSDRate * MULTIPLIER) / _zTokenFromUSDRate);
        mintAmount = mintAmount / MULTIPLIER;

        bool burnSuccess = _burn(_zTokenFrom, msg.sender, _amountWithDecimal);

        if (!burnSuccess) revert BurnFailed();

        bool mintSuccess = _mint(_zTokenTo, msg.sender, mintAmount);

        if (!mintSuccess) revert MintFailed();

        /**
         * Handle swap fees and rewards
         */
        globalMintersFeePerTransaction =
            (globalMintersPercentOfSwapFee * swapFeePerTransactionInUsd) /
            MULTIPLIER;

        globalMintersFee += globalMintersFeePerTransaction;

        treasuryFeePerTransaction =
            (treasuryPercentOfSwapFee * swapFeePerTransactionInUsd) /
            MULTIPLIER;

        /**
         * Send the treasury amount from User to a treasury wallet
         */
        IERC20(zUSD).transferFrom(
            msg.sender,
            treasuryWallet,
            treasuryFeePerTransaction
        );

        /**
         * @TODO - Implement a more elegent solution
         * Send the global minters fee from User to the global minters fee wallet
         */
        IERC20(zUSD).transferFrom(
            msg.sender,
            mintersWallet,
            globalMintersFeePerTransaction
        );

        /**
         * @TODO - Send the remaining fee to all minters
         */
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
        address _zToken,
        uint256 _zTokenUSDRate,
        uint256 zNGNUSDRate,
        uint256 zCFAUSDRate,
        uint256 zZARUSDRate
    ) external nonReentrant {
        uint256 _amountToRepayWithDecimal = _getDecimal(_amountToRepay);
        uint256 _amountToWithdrawWithDecimal = _getDecimal(_amountToWithdraw);

        uint256 amountToRepayinUSD = _repay(
            _amountToRepayWithDecimal,
            _zToken,
            _zTokenUSDRate
        );

        uint256 userDebt;

        userDebt = _updateUserDebtOutstanding(
            netMintUser[msg.sender],
            netMintGlobal,
            zNGNUSDRate,
            zCFAUSDRate,
            zZARUSDRate
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

        /**
         * Substract withdraw from current net mint value and assign new mint value
         */
        uint256 amountToSubtract = ((netMintUser[msg.sender] *
            amountToRepayinUSD) / User[msg.sender].userDebtOutstanding);

        netMintUser[msg.sender] -= amountToSubtract;

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

        _testImpact(zNGNUSDRate, zCFAUSDRate, zZARUSDRate);

        emit Withdraw(msg.sender, _zToken, _amountToWithdraw);
    }

    function liquidate(
        address _user,
        uint256 zNGNUSDRate,
        uint256 zCFAUSDRate,
        uint256 zZARUSDRate
    ) external nonReentrant {
        uint256 userDebt;
        uint256 userCollateralRatio;

        /**
         * Update the user's debt balance with latest price feeds
         */
        userDebt = _updateUserDebtOutstanding(
            netMintUser[_user],
            netMintGlobal,
            zNGNUSDRate,
            zCFAUSDRate,
            zZARUSDRate
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

        // _testImpact(zNGNUSDRate, zCFAUSDRate, zZARUSDRate);

        /**
         * Get reward fee
         * Send the equivalent of debt as collateral and also a 10% fee to the liquidator
         */
        uint256 rewardFee = (userDebt * LIQUIDATION_REWARD) / 100;

        uint256 totalRewards = userDebt + rewardFee;

        bool transferSuccess = IERC20(collateral).transfer(
            msg.sender,
            totalRewards
        );

        if (!transferSuccess) revert TransferFailed();

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
     * set collaterization ratio threshold
     */
    function setCollaterizationRatioThreshold(uint256 value)
        external
        onlyOwner
    {
        COLLATERIZATION_RATIO_THRESHOLD = value;
    }

    /**
     * set liquidation reward
     */
    function setLiquidationReward(uint256 value) external onlyOwner {
        LIQUIDATION_REWARD = value;
    }

    /**
     * Change swap variables
     */
    function addTreasuryWallet(address _address) external onlyOwner {
        treasuryWallet = _address;
    }

    function addMintersWallet(address _address) external onlyOwner {
        mintersWallet = _address;
    }

    function changeSwapFee(uint256 numerator, uint256 denominator)
        external
        onlyOwner
    {
        swapFee = WadRayMath.wadDiv(numerator, denominator);
    }

    function changeGlobalMintersFee(uint256 numerator, uint256 denominator)
        external
        onlyOwner
    {
        globalMintersPercentOfSwapFee = WadRayMath.wadDiv(
            numerator,
            denominator
        );
    }

    function changeTreasuryFee(uint256 numerator, uint256 denominator)
        external
        onlyOwner
    {
        treasuryPercentOfSwapFee = WadRayMath.wadDiv(numerator, denominator);
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
    ) internal virtual returns (bool) {
        ZTokenInterface(_tokenAddress).mint(_userAddress, _amount);

        return true;
    }

    function _burn(
        address _tokenAddress,
        address _userAddress,
        uint256 _amount
    ) internal virtual returns (bool) {
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
        zUSDMintAmount = (_amount * 1) / _zTokenUsdRate;

        _burn(_zToken, msg.sender, _amount);

        _mint(zUSD, msg.sender, zUSDMintAmount);

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
     * Get User Outstanding Debt
     */

    function _updateUserDebtOutstanding(
        uint256 _netMintUserzUSDValue,
        uint256 _netMintGlobalzUSDValue,
        uint256 zNGNUSDRate,
        uint256 zCFAUSDRate,
        uint256 zZARUSDRate
    ) public view returns (uint256) {
        require(
            _netMintGlobalzUSDValue > 0,
            "Global zUSD mint too low, underflow may occur"
        );

        uint256 userDebtOutstanding;
        uint256 globalDebt;
        uint256 mintRatio;

        globalDebt =
            IERC20(zUSD).totalSupply() +
            WadRayMath.wadDiv(IERC20(zNGN).totalSupply(), zNGNUSDRate) +
            WadRayMath.wadDiv(IERC20(zCFA).totalSupply(), zCFAUSDRate) +
            WadRayMath.wadDiv(IERC20(zZAR).totalSupply(), zZARUSDRate);

        globalDebt = globalDebt / MULTIPLIER;

        mintRatio = WadRayMath.wadDiv(
            _netMintUserzUSDValue,
            _netMintGlobalzUSDValue
        );

        userDebtOutstanding = mintRatio * globalDebt;

        userDebtOutstanding = userDebtOutstanding / MULTIPLIER;

        return userDebtOutstanding;
    }

    /**
     * Helper function to test the impact of a transaction i.e mint, burn, deposit or withdrawal by a user
     */
    function _testImpact(
        uint256 zNGNUSDRate,
        uint256 zCFAUSDRate,
        uint256 zZARUSDRate
    ) internal view returns (bool) {
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
                netMintGlobal,
                zNGNUSDRate,
                zCFAUSDRate,
                zZARUSDRate
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
