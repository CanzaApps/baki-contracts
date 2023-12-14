// SPDX-License-Identifier: MIT

/**
 * NOTE
 * Always do additions first
 * Check if the substracting value is greater than or less than the added values i.e check for a negative result
 */

pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ZTokenInterface.sol";
import "./libraries/WadRayMath.sol";
import "./interfaces/BakiOracleInterface.sol";

error MintFailed();
error BurnFailed();

contract Vault is
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    
    IERC20Upgradeable public collateral;

    address private Oracle;

    address public zUSD;

    uint256 private constant MULTIPLIER = 1e6;

    uint256 private constant HALF_MULTIPLIER = 1e3;

    uint256 public COLLATERIZATION_RATIO_THRESHOLD;

    uint256 public LIQUIDATION_REWARD;

    /**
     * Net User Mint
     * Maps user address => cumulative mint value
     */
    mapping(address => uint256) public netMintUser;

    mapping(address => uint256) public grossMintUser;

    mapping(address => uint256) public userCollateralBalance;

    /**
     * Net Global Mint
     */
    uint256 public netMintGlobal;

    mapping(address => uint256) public userAccruedFeeBalance;

    mapping(address => uint256) private mintersRewardPerTransaction;

    uint256 public globalMintersFee;

    address public treasuryWallet;

    uint256 public  swapFee;

    uint256 public globalMintersPercentOfSwapFee;

    uint256 public treasuryPercentOfSwapFee;

    /** run-time In function variables */
    uint256 swapFeePerTransactionInUsd;
    uint256 swapFeePerTransaction;
    uint256 globalMintersFeePerTransaction;
    uint256 treasuryFeePerTransaction;

    address[] public mintersAddresses;

    address[] public _blacklistedAddresses;

    address[] public usersInLiquidationZone;

    uint256 public totalCollateral;

    uint256 private swapAmountInUSD;

    uint256 public totalSwapVolume;

    mapping(address => bool) public isUserBlacklisted;

    bool public TxPaused;

    mapping(address => bool) public isMinter;

    bytes32 public constant CONTROLLER = keccak256("CONTROLLER");

    mapping(address => uint256) public GlobalMintersFeeAtClaim;

    mapping(address => uint256) public lastUserCollateralRatio;

    uint256 private constant USDC_DIVISOR = 1e12;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
    _disableInitializers();
    }

     function vault_init(
        address _controller,
        address _oracle,
        IERC20Upgradeable _collateral,
        address _zusd
    ) external initializer {
        TxPaused = false;
        Oracle = _oracle;
        collateral = _collateral;
        zUSD = _zusd;
        COLLATERIZATION_RATIO_THRESHOLD = 15 * 1e2;
        LIQUIDATION_REWARD = 15;
        treasuryWallet = 0x9e0FBB6c48E571744c09d695552Ad20d44C3fC50;
        swapFee = WadRayMath.wadDiv(8, 1000);
        globalMintersPercentOfSwapFee = WadRayMath.wadDiv(1, 2);
        treasuryPercentOfSwapFee = WadRayMath.wadDiv(1, 2);
        _setupRole(CONTROLLER, _controller);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        __Ownable_init();
        __ReentrancyGuard_init();
        __AccessControl_init();
    }

    /**
     * @dev
     */

    event Deposit(
        address indexed _account,
        uint256 indexed _depositAmount,
        uint256 indexed _mintAmount
    );
    event Swap(
        string _zTokenFrom,
        uint256 _amount
    );
    event Withdraw(
        address indexed _account,
        string _token,
        uint256 _amountToWithdraw
    );
    event Liquidate(
        address indexed _account,
        uint256 debt,
        uint256 rewards,
        address liquidator
    );

    event SetCollaterizationRatioThreshold(uint256 _value);

    event SetLiquidationReward(uint256 _value);

    event AddAddressToBlacklist(address _address);

    event RemoveAddressFromBlacklist(address _address);

    event PauseTransactions();

    event AddTreasuryWallet(address _address);

    event ChangeSwapFee(uint256 a, uint256 b);

    event FeeSetting(uint256 a, uint256 b, uint256 x, uint256 y);

    event SetOracleAddress(address _address);

    /** 
    @notice Allows a user to deposit cUSD collateral in exchange for some amount of zUSD.
     _depositAmount  The amount of cUSD the user sent in the transaction
     */
    function depositAndMint(
        uint256 _depositAmount,
        uint256 _mintAmount
    ) external nonReentrant {
        blockBlacklistedAddresses(msg.sender);
        isTxPaused();
        
        uint256 depositAmountInUSDC = _depositAmount / USDC_DIVISOR;

        require(
            collateral.balanceOf(msg.sender) >=
                depositAmountInUSDC,
                "Insufficient Balance"
        );

        userCollateralBalance[msg.sender] += _depositAmount;

        totalCollateral += _depositAmount;

        uint256 globalDebt = getGlobalDebt();

        uint256 netMintChange;

        _mint(zUSD, msg.sender, _mintAmount);

        if(globalDebt == 0 || netMintGlobal == 0) {
            netMintChange = _mintAmount;
        } else {
            netMintChange = netMintGlobal * _mintAmount * MULTIPLIER / globalDebt;

             if (netMintChange < MULTIPLIER && netMintChange > 0) {
            netMintChange = 1;
            } else {
                netMintChange = netMintChange / MULTIPLIER;
            }
        }

        grossMintUser[msg.sender] += _mintAmount;

        netMintUser[msg.sender] += netMintChange;
        netMintGlobal += netMintChange;  

        /**
         * if this is user's first mint, add to minters list
         */
        if (!isMinter[msg.sender] && grossMintUser[msg.sender] > 0) {
            mintersAddresses.push(msg.sender);
            isMinter[msg.sender] = true;
        }

        lastUserCollateralRatio[msg.sender] = getUserCollateralRatio(msg.sender);

        _testImpact();

        collateral.safeTransferFrom(
            msg.sender,
            address(this),
            depositAmountInUSDC
        );

        emit Deposit(msg.sender, _depositAmount, _mintAmount);
    }

    /**
     * Allows a user to swap zUSD for other zTokens using their exchange rates
     */
    function swap(
        uint256 _amount,
        string calldata _zTokenFrom,
        string calldata _zTokenTo
    ) external nonReentrant {
        blockBlacklistedAddresses(msg.sender);
        isTxPaused();

        uint256 swapAmount;
        uint256 mintAmount;
        address _zTokenFromAddress = BakiOracleInterface(Oracle).getZToken(_zTokenFrom);
        address _zTokenToAddress = BakiOracleInterface(Oracle).getZToken(_zTokenTo);

        require(
            IERC20Upgradeable(_zTokenFromAddress).balanceOf(msg.sender) >= _amount,
            "Insufficient Balance"
        );
        uint256 _zTokenFromUSDRate = BakiOracleInterface(Oracle).getZTokenUSDValue(_zTokenFrom);
        uint256 _zTokenToUSDRate = BakiOracleInterface(Oracle).getZTokenUSDValue(_zTokenTo);

        /**
         * Get the USD values of involved zTokens
         * Handle minting of new tokens and burning of user tokens
         */
        swapAmount = (_amount * _zTokenToUSDRate);

        swapAmount = swapAmount / _zTokenFromUSDRate;

        swapFeePerTransaction = swapFee * swapAmount;

        swapFeePerTransaction = swapFeePerTransaction / MULTIPLIER;

        swapFeePerTransactionInUsd = swapFeePerTransaction * HALF_MULTIPLIER;

        swapFeePerTransactionInUsd =
            swapFeePerTransactionInUsd /
            _zTokenToUSDRate;

        mintAmount = swapAmount - swapFeePerTransaction;

        /**
        * Track the USD value of the swap amount
        */
        uint256 x = _amount * HALF_MULTIPLIER;
        swapAmountInUSD = x / _zTokenFromUSDRate;

        totalSwapVolume += swapAmountInUSD;

        _burn(_zTokenFromAddress, msg.sender, _amount);

        _mint(_zTokenToAddress, msg.sender, mintAmount);

        /**
         * Handle swap fees and rewards
         */
        globalMintersFeePerTransaction =
            globalMintersPercentOfSwapFee *
            swapFeePerTransactionInUsd;

        globalMintersFeePerTransaction =
            globalMintersFeePerTransaction /
            MULTIPLIER;

        globalMintersFee += globalMintersFeePerTransaction;

        treasuryFeePerTransaction =
            treasuryPercentOfSwapFee *
            swapFeePerTransactionInUsd;

        treasuryFeePerTransaction = treasuryFeePerTransaction / MULTIPLIER;

        /**
         * Send the treasury amount to a treasury wallet
         */
         _mint(zUSD, treasuryWallet, treasuryFeePerTransaction);

        emit Swap(_zTokenFrom, _amount);
    }

    /**
     * Allows to user to repay and/or withdraw their collateral
     */
    function repayAndWithdraw(
        uint256 _amountToRepay,
        uint256 _amountToWithdraw,
        string calldata _zToken
    ) external nonReentrant {
        blockBlacklistedAddresses(msg.sender);
        isTxPaused();

        uint256 amountToRepayinUSD = _repay(_amountToRepay, _zToken);

        uint256 userDebt;

        userDebt = _updateUserDebtOutstanding(
            netMintUser[msg.sender],
            netMintGlobal
        );

        require(
            userCollateralBalance[msg.sender] >= _amountToWithdraw,
            "Insufficient Collateral"
        );

        require(
            userDebt >= amountToRepayinUSD,
            "Repay>Debt"
        );

        if (userDebt != 0) {
            uint256 amountToSubtract = (netMintUser[msg.sender] *
                amountToRepayinUSD) / userDebt;

            netMintUser[msg.sender] -= amountToSubtract;

            netMintGlobal -= amountToSubtract;
        }

        _burn(zUSD, msg.sender, amountToRepayinUSD);

        userCollateralBalance[msg.sender] -= _amountToWithdraw;

        totalCollateral -= _amountToWithdraw;

        lastUserCollateralRatio[msg.sender] = getUserCollateralRatio(msg.sender);

        _testImpact();

        uint256 amountToWithdrawInUSDC = _amountToWithdraw / USDC_DIVISOR;

        collateral.safeTransfer(
            msg.sender,
            amountToWithdrawInUSDC
        );

        emit Withdraw(msg.sender, _zToken, _amountToWithdraw);
    }

    function liquidate(address _user) external nonReentrant {
        blockBlacklistedAddresses(msg.sender);
        isTxPaused();

        uint256 userDebt;

        uint256 totalRewards = getPotentialTotalReward(_user);

        userDebt = _updateUserDebtOutstanding(
            netMintUser[_user],
            netMintGlobal
        );

        require(
            IERC20Upgradeable(zUSD).balanceOf(msg.sender) >= userDebt,
            "!LzUSD"
        );

        netMintGlobal = netMintGlobal - netMintUser[_user];
        netMintUser[_user] = 0;

        _burn(zUSD, msg.sender, userDebt);

        uint256 totalRewardsInUSDC = totalRewards / USDC_DIVISOR;

        if (userCollateralBalance[_user] <= totalRewards) {
            userCollateralBalance[_user] = 0;

            totalCollateral -= totalRewards;

            collateral.safeTransfer(
                msg.sender,
                totalRewardsInUSDC
            );

        } else {
            userCollateralBalance[_user] -= totalRewards;

            totalCollateral -= totalRewards;

            collateral.safeTransfer(
                msg.sender,
                totalRewardsInUSDC
            );
        }

        emit Liquidate(_user, userDebt, totalRewards, msg.sender);
    }

    /**
     * Get potential total rewards from user in liquidation zone
     */
    function getPotentialTotalReward(
        address _user
    ) public view returns (uint256) {
        bool isUserInLiquidationZone = checkUserForLiquidation(_user);

        uint256 rate = BakiOracleInterface(Oracle).collateralUSD();

        uint256 _userDebt = _updateUserDebtOutstanding(
            netMintUser[_user],
            netMintGlobal
        );

        require(
            isUserInLiquidationZone == true,
            "Not in liquidation Zone"
        );
        require(_userDebt > 0, "Insufficient Debt");

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
    function manageUsersInLiquidationZone()
        external
        returns (address[] memory)
    {
        require(hasRole(CONTROLLER, msg.sender), " Not controller");

        uint len = mintersAddresses.length;

        for (uint256 i; i < len; i++) {
            bool isUserInLiquidationZone = checkUserForLiquidation(
                mintersAddresses[i]
            );
            bool isUserAlreadyInLiquidationArray = _checkIfUserAlreadyExistsInLiquidationList(
                    mintersAddresses[i]
                );

            // If a user is in liquidation zone and not in the liquidation list, add user to the list
            if (
                isUserInLiquidationZone == true &&
                isUserAlreadyInLiquidationArray == false
            ) {
                usersInLiquidationZone.push(mintersAddresses[i]);
            }

            // If the user is not/ no longer in the liquidation zone but still in the list, remove from the list
            if (
                isUserInLiquidationZone == false &&
                isUserAlreadyInLiquidationArray == true
            ) {
                _removeUserFromLiquidationList(mintersAddresses[i]);
            }
        }
        return usersInLiquidationZone;
    }

    function getUserFromLiquidationZone()
        external
        view
        returns (address[] memory)
    {
        return usersInLiquidationZone;
    }

    /**
     * Helper function to check that a user is already present in liquidation list
     */
    function _checkIfUserAlreadyExistsInLiquidationList(
        address _user
    ) internal view returns (bool) {
        uint len = usersInLiquidationZone.length;

        for (uint256 i; i < len; i++) {
            if (usersInLiquidationZone[i] == _user) {
                return true;
            }
        }
        return false;
    }

    /**
     * Helper function to remove a user from the liquidation list
     */
    function _removeUserFromLiquidationList(address _user) internal {
        bool isUserAlreadyInLiquidationArray = _checkIfUserAlreadyExistsInLiquidationList(
                _user
            );

        require(
            isUserAlreadyInLiquidationArray == true,
            "!LZ"
        );

        uint256 index;

        uint len = usersInLiquidationZone.length;

        for (uint256 i; i < len; i++) {
            if (usersInLiquidationZone[i] == _user) {
                index = i;
            }
        }
        usersInLiquidationZone[index] = usersInLiquidationZone[
            usersInLiquidationZone.length - 1
        ];

        usersInLiquidationZone.pop();
    }

    /**
     * Check User for liquidation
     */
    function checkUserForLiquidation(address _user) public view returns (bool) {
        require(_user != address(0), "ZA");

         uint256 userColRatio = getUserCollateralRatio(_user);

            if (userColRatio < COLLATERIZATION_RATIO_THRESHOLD && userColRatio != 0) {
                return true;
            }

        return false;
    }

    /**
     * Get user balance
     */
    function getBalance(address _token) external view returns (uint256) {
        return IERC20Upgradeable(_token).balanceOf(msg.sender);
    }

    /**
     * @dev Returns the minted token value for a particular user
     */
    function getNetUserMintValue(
        address _address
    ) external view returns (uint256) {
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
      function setCollaterizationRatioThreshold(
        uint256 _value
    ) external onlyOwner {
        // Set an upper and lower bound on the new value of collaterization ratio threshold
        require(
            _value > 12 * 1e2 && _value < 20 * 1e2,
            "!SL"
        );

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
     * Check for blacklisted address
     */
       function blacklistAddress(address _address) external onlyOwner {

        require(!isUserBlacklisted[_address],"BA");

        isUserBlacklisted[_address] = true;

        emit AddAddressToBlacklist(_address);
    }

    /**
     * Remove from blacklist
     */
    function removeAddressFromBlacklist(address _address) external onlyOwner {

        require(isUserBlacklisted[_address], "!BA");

        isUserBlacklisted[_address] = false;

        emit RemoveAddressFromBlacklist(_address);
    }
    /**
     * Pause transactions
     */
    function pause() external onlyOwner {
       require(TxPaused == false, "TxP true");

       TxPaused = true;

       emit PauseTransactions();
    }

       /**
     * Pause transactions
     */
    function unPause() external onlyOwner {
        require(TxPaused == true, "TxP false");

        TxPaused = false;

    }

    /**
     * Change swap variables
     */
    function addTreasuryWallet(address _address) external onlyOwner{
        require(_address != address(0), "ZA");

        treasuryWallet = _address;

        emit AddTreasuryWallet(_address);
    }

    function changeSwapFee(uint256 a, uint256 b) external onlyOwner {
        swapFee = WadRayMath.wadDiv(a, b);

        require(swapFee <= MULTIPLIER, "IsF");

        emit ChangeSwapFee(a, b);
    }

   
    function feeSetting(uint256 a, uint256 b, uint256 x, uint256 y) external onlyOwner {
        globalMintersPercentOfSwapFee = WadRayMath.wadDiv(a, b);
        treasuryPercentOfSwapFee = WadRayMath.wadDiv(x, y);

        uint256 sum = globalMintersPercentOfSwapFee + treasuryPercentOfSwapFee;

        require(sum == MULTIPLIER, "IFS");

        emit FeeSetting(a, b, x, y);
    }

    /**
     * Get Total Supply of zTokens
     */
    function getTotalSupply(address _address) external view returns (uint256) {
        return IERC20Upgradeable(_address).totalSupply();
    }

    /**
     * Get total number of minters
     */
    function getTotalMinters() external view returns (uint256) {
        return mintersAddresses.length;
    }

    /**
     * view minters addresses
     */
    function viewMintersAddress(uint256 start, uint256 pageSize) external view returns (address[] memory) {
        uint len = mintersAddresses.length;

        require(start < len, "out of range");

        uint256 end = start + pageSize;
        if (end > len) {
            end = len;
        }

        address[] memory result = new address[](end - start);

        for (uint256 i = start; i < end; i++) {
            result[i - start] = mintersAddresses[i];
        }

        return result;
    }

    /**
     * Private functions
     */
    function _mint(
        address _tokenAddress,
        address _userAddress,
        uint256 _amount
    ) internal {
        bool success = ZTokenInterface(_tokenAddress).mint(
            _userAddress,
            _amount
        );

        if (!success) revert MintFailed();
    }

    function _burn(
        address _tokenAddress,
        address _userAddress,
        uint256 _amount
    ) internal {
        bool success = ZTokenInterface(_tokenAddress).burn(
            _userAddress,
            _amount
        );

        if (!success) revert BurnFailed();
    }

    /**
     * Allows a user swap back their zTokens to zUSD
     */
    function _repay(
        uint256 _amount,
        string calldata _zToken
    ) internal returns (uint256) {
        uint256 zUSDMintAmount = _amount;
        address _zTokenAddress = BakiOracleInterface(Oracle).getZToken(_zToken);

        /**
         * If the token to be repayed is zUSD, skip the fees, mint, burn process and return the _amount directly
         */
        if (_zTokenAddress != zUSD) {
            uint256 zTokenUSDRate = BakiOracleInterface(Oracle).getZTokenUSDValue(_zToken);

            swapFeePerTransaction = swapFee * _amount;

            swapFeePerTransaction = swapFeePerTransaction / MULTIPLIER;

            swapFeePerTransactionInUsd =
                swapFeePerTransaction *
                HALF_MULTIPLIER;

            swapFeePerTransactionInUsd =
                swapFeePerTransactionInUsd /
                zTokenUSDRate;

            /**
             * Get the amount to mint in zUSD
             */
            zUSDMintAmount = _amount - swapFeePerTransaction;

            zUSDMintAmount = zUSDMintAmount * HALF_MULTIPLIER;

            zUSDMintAmount = zUSDMintAmount / zTokenUSDRate;

            /**
            * Track the USD value of the swap amount
            */
            uint256 x = _amount * HALF_MULTIPLIER;
            swapAmountInUSD = x / zTokenUSDRate;

            totalSwapVolume += swapAmountInUSD;

            _burn(_zTokenAddress, msg.sender, _amount);

            _mint(zUSD, msg.sender, zUSDMintAmount);
            
            globalMintersFeePerTransaction =
                globalMintersPercentOfSwapFee *
                swapFeePerTransactionInUsd;

            globalMintersFeePerTransaction =
                globalMintersFeePerTransaction /
                MULTIPLIER;

            globalMintersFee += globalMintersFeePerTransaction;

            treasuryFeePerTransaction =
                treasuryPercentOfSwapFee *
                swapFeePerTransactionInUsd;

            treasuryFeePerTransaction = treasuryFeePerTransaction / MULTIPLIER;

            /**
             * Send the treasury amount to a treasury wallet
             */
            _mint(zUSD, treasuryWallet, treasuryFeePerTransaction);
        }

        return zUSDMintAmount;
    }

    /**
     * Set Oracle contract address
     */
   function setOracleAddress(address _address) external onlyOwner {
        require(_address != address(0), "ZA");

        Oracle = _address;

        emit SetOracleAddress(_address);
    }

    /**
     * Returns the USD value of user's collateral
     */
    function getUSDValueOfCollateral(
        uint256 _amount
    ) internal view returns (uint256) {
        uint256 USDValue;
        uint256 rate;

        rate = BakiOracleInterface(Oracle).collateralUSD();

        USDValue = _amount * rate;
        USDValue = USDValue / HALF_MULTIPLIER;
        return USDValue;
    }

    /**
    * Get address of zUSD token
    */
    function getzUSDAddress() external onlyOwner returns(address) {
        return zUSD = BakiOracleInterface(Oracle).getZToken("zusd");
    }

    /**
     * Helper function for global debt 
     */
    function getDebtHelper(string memory _zToken) internal view returns(uint256) {
        address _zTokenAddress = BakiOracleInterface(Oracle).getZToken(_zToken);

        uint256 singleZToken = WadRayMath.wadDiv(IERC20Upgradeable(_zTokenAddress).totalSupply(), 
        BakiOracleInterface(Oracle).getZTokenUSDValue(_zToken)
        );

        return (singleZToken / HALF_MULTIPLIER);
    }

    /**
     * Get Global Debt
     */
  function getGlobalDebt() public view returns (uint256) {
        uint256 globalDebt;
        string[] memory zTokenList = BakiOracleInterface(Oracle).getZTokenList();
        
        for(uint256 i = 0; i < zTokenList.length; i++) {
            string memory zToken = zTokenList[i];

            globalDebt += getDebtHelper(zToken);
        }

        return globalDebt;
    }

    function getUserDebt(address user) public view returns (uint256) {
        return _updateUserDebtOutstanding(netMintUser[user], netMintGlobal);
    }

    /**
     * Get collateral ratio i.e ratio of user collateral balance to debt
     * This function calculates the latest/realtime value of collateral ratio
     */
     function getUserCollateralRatio(address user) public view returns (uint256) {
        uint256 USDValueOfCollateral;
        uint256 userDebt = getUserDebt(user);

        USDValueOfCollateral = getUSDValueOfCollateral(
            userCollateralBalance[user]
        );

        if( userDebt != 0) {
            uint256 x = WadRayMath.wadDiv(USDValueOfCollateral, userDebt);

            x = x / HALF_MULTIPLIER;

            return x;
        }

        return USDValueOfCollateral;
    }

    /**
     * This returns the collateral ratio of a user at the last user deposit or withdraw
     */
    function returnLastCollateralRatio(address user) public view returns (uint256) {
        return lastUserCollateralRatio[user];
    }

    /**
     * Get User Outstanding Debt
     */
 function _updateUserDebtOutstanding(
        uint256 _netMintUserzUSDValue,
        uint256 _netMintGlobalzUSDValue
    ) internal view returns (uint256) {
        if (_netMintGlobalzUSDValue != 0) {
            uint256 globalDebt = getGlobalDebt();
            uint256 userDebtOutstanding;
            uint256 mintRatio;

            uint256 temp = _netMintUserzUSDValue * globalDebt;

            mintRatio = WadRayMath.wadDiv(
                temp,
                _netMintGlobalzUSDValue
            );

            userDebtOutstanding = mintRatio / MULTIPLIER;

            return userDebtOutstanding;
        }
        return 0;
    }

    /**
     * @dev modifier to check for blacklisted addresses
     */
    function blockBlacklistedAddresses(address _address) internal view {
        require(!isUserBlacklisted[_address], "BL");
    }

    function isTxPaused() internal view {
        require(TxPaused == false, "TP");
    }

    /**
     * Helper function to test the impact of a transaction i.e mint, burn, deposit or withdrawal by a user
     */
     function _testImpact() internal view returns (bool) {
        uint256 userDebt;
        uint256 USDValueOfCollateral;

        USDValueOfCollateral = getUSDValueOfCollateral(
            userCollateralBalance[msg.sender]
        );

        /**
         * If the netMintGlobal is 0, then debt doesn't exist
         */
        if (netMintGlobal != 0) {
            userDebt = _updateUserDebtOutstanding(
                netMintUser[msg.sender],
                netMintGlobal
            );

            uint256 collateralRatioMultipliedByDebt = (userDebt *
                COLLATERIZATION_RATIO_THRESHOLD) / HALF_MULTIPLIER;

            require(
                USDValueOfCollateral >= collateralRatioMultipliedByDebt,
                "Insufficent Collateral"
            );
        }

        return true;
    }

    uint256[49] private __gap;
}
