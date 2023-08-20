// SPDX-License-Identifier: MIT

/**
 * NOTE
 * Always do additions first
 * Check if the substracting value is greater than or less than the added values i.e check for a negative result
 */

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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

contract Vault is
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;
    
    IERC20 public collateral;

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

    bool public transactionsPaused;

    address[] public usersInLiquidationZone;

    uint256 public totalCollateral;

    uint256 private swapAmountInUSD;

    uint256 public totalSwapVolume;

    mapping(address => bool) public isUserBlacklisted;

    bool public TxPaused;

    mapping(address => bool) public isMinter;

    /**
     * Initializers
     */

     function vault_init(
        address _oracle,
        IERC20 _collateral
    ) external initializer {
        TxPaused = false;
        Oracle = _oracle;
        collateral = _collateral;
        COLLATERIZATION_RATIO_THRESHOLD = 15 * 1e2;
        LIQUIDATION_REWARD = 15;
        treasuryWallet = 0x6F996Cb36a2CB5f0e73Fc07460f61cD083c63d4b;
        swapFee = WadRayMath.wadDiv(8, 1000);
        globalMintersPercentOfSwapFee = WadRayMath.wadDiv(1, 2);
        treasuryPercentOfSwapFee = WadRayMath.wadDiv(1, 2);

        __Ownable_init();
        __ReentrancyGuard_init();
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
        address indexed _account,
        string _zTokenFrom,
        string _zTokenTo
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

    event ChangeGlobalMintersFee(uint256 a, uint256 b);

    event ChangeTreasuryFee(uint256 a, uint256 b);

    event SetOracleAddress(address _address);

    /** 
    @notice Allows a user to deposit cUSD collateral in exchange for some amount of zUSD.
     _depositAmount  The amount of cUSD the user sent in the transaction
     */
    function depositAndMint(
        uint256 _depositAmount,
        uint256 _mintAmount
    ) external payable nonReentrant {
        blockBlacklistedAddresses(msg.sender);
        isTxPaused();
        
        require(
            collateral.balanceOf(msg.sender) >=
                _depositAmount,
            "IB"
        );

        collateral.safeTransferFrom(
            msg.sender,
            address(this),
            _depositAmount
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

            netMintChange = netMintChange / MULTIPLIER ;
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

        _testImpact();

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
            IERC20(_zTokenFromAddress).balanceOf(msg.sender) >= _amount,
            "IB"
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
        swapAmountInUSD = _amount * HALF_MULTIPLIER;
        swapAmountInUSD = _amount / _zTokenFromUSDRate;

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

        getSwapReward();

        treasuryFeePerTransaction =
            treasuryPercentOfSwapFee *
            swapFeePerTransactionInUsd;

        treasuryFeePerTransaction = treasuryFeePerTransaction / MULTIPLIER;

        /**
         * Send the treasury amount to a treasury wallet
         */
         _mint(zUSD, treasuryWallet, treasuryFeePerTransaction);

        /**
         * Send the global minters fee from User to the global minters fee wallet
         */
        _mint(zUSD, address(this), globalMintersFeePerTransaction);

        emit Swap(msg.sender, _zTokenFrom, _zTokenTo);
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
            "IC"
        );

        require(
            userDebt >= amountToRepayinUSD,
            "A>D"
        );

        if (userDebt != 0) {
            uint256 amountToSubtract = (netMintUser[msg.sender] *
                amountToRepayinUSD) / userDebt;

            netMintUser[msg.sender] -= amountToSubtract;

            netMintGlobal -= amountToSubtract;
        }

        _burn(zUSD, msg.sender, amountToRepayinUSD);

        userCollateralBalance[msg.sender] -= _amountToWithdraw;

        collateral.safeTransfer(
            msg.sender,
            _amountToWithdraw
        );

        _testImpact();

        emit Withdraw(msg.sender, _zToken, _amountToWithdraw);
    }

    function liquidate(address _user) external nonReentrant {
        blockBlacklistedAddresses(msg.sender);
        isTxPaused();

        uint256 userDebt;

        bool isUserInLiquidationZone = checkUserForLiquidation(_user);
        require(
            isUserInLiquidationZone == true,
            "!LZ"
        );

        uint totalRewards = getPotentialTotalReward(_user);

        userDebt = _updateUserDebtOutstanding(
            netMintUser[_user],
            netMintGlobal
        );

        require(
            IERC20(zUSD).balanceOf(msg.sender) >= userDebt,
            "!LzUSD"
        );

        netMintGlobal = netMintGlobal - netMintUser[_user];
        netMintUser[_user] = 0;

        _burn(zUSD, msg.sender, userDebt);

        if (userCollateralBalance[_user] <= totalRewards) {
            userCollateralBalance[_user] = 0;

            collateral.safeTransfer(
                msg.sender,
                totalRewards
            );

        } else {
            userCollateralBalance[_user] -= totalRewards;

            collateral.safeTransfer(
                msg.sender,
                totalRewards
            );
        }

        emit Liquidate(_user, userDebt, totalRewards, msg.sender);
    }

    /**
     * Allow minters to claim rewards/fees on swap
     */
    function claimFees() external nonReentrant {
        require(
            userAccruedFeeBalance[msg.sender] > 0,
            "!UR"
        );
        uint256 amount;

        amount = userAccruedFeeBalance[msg.sender];
        userAccruedFeeBalance[msg.sender] = 0;

        bool transferSuccess = IERC20(zUSD).transfer(msg.sender, amount);
        if (!transferSuccess) revert();
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
            "!LZ"
        );
        require(_userDebt > 0, "!UD");

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
        onlyOwner
        returns (address[] memory)
    {
        for (uint256 i = 0; i < mintersAddresses.length; i++) {
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
        for (uint256 i = 0; i < usersInLiquidationZone.length; i++) {
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

        for (uint256 i = 0; i < usersInLiquidationZone.length; i++) {
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

        uint256 userDebt;
        uint256 userCollateralRatio;

        uint256 USDValueOfCollateral = getUSDValueOfCollateral(
            userCollateralBalance[_user]
        );

        userDebt = _updateUserDebtOutstanding(
            netMintUser[_user],
            netMintGlobal
        );

        if (userDebt != 0) {
            userCollateralRatio =
                1e3 *
                WadRayMath.wadDiv(USDValueOfCollateral, userDebt);

            userCollateralRatio = userCollateralRatio / MULTIPLIER;

            if (userCollateralRatio < COLLATERIZATION_RATIO_THRESHOLD) {
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
    ) external {
        // Set an upper and lower bound on the new value of collaterization ratio threshold
        require(
            _value > 12 * 1e2 || _value < 20 * 1e2,
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
       function blacklistAddress(address _address) external {

        require(!isUserBlacklisted[_address],"BA");

        isUserBlacklisted[_address] = true;

        emit AddAddressToBlacklist(_address);
    }

    /**
     * Remove from blacklist
     */
    function removeAddressFromBlacklist(address _address) external {

        require(isUserBlacklisted[_address], "!BA");

        isUserBlacklisted[_address] = false;

        emit RemoveAddressFromBlacklist(_address);
    }
    /**
     * Pause transactions
     */
    function pause() external {
       require(TxPaused = false, "TxP true");

       TxPaused = true;

       emit PauseTransactions();
    }

       /**
     * Pause transactions
     */
    function unPause() external {
        require(TxPaused = true, "TxP false");

        TxPaused = false;

    }

    /**
     * Change swap variables
     */
    function addTreasuryWallet(address _address) external {
        require(_address != address(0), "ZA");

        treasuryWallet = _address;

        emit AddTreasuryWallet(_address);
    }

    function changeSwapFee(uint256 a, uint256 b) external onlyOwner {
        swapFee = WadRayMath.wadDiv(a, b);

        require(swapFee <= MULTIPLIER, "IsF");

        emit ChangeSwapFee(a, b);
    }

    function changeGlobalMintersFee(uint256 a, uint256 b) external onlyOwner {
        globalMintersPercentOfSwapFee = WadRayMath.wadDiv(a, b);

        uint256 x = globalMintersPercentOfSwapFee + treasuryPercentOfSwapFee;

        require(x == MULTIPLIER, "IGMF");

        emit ChangeGlobalMintersFee(a, b);
    }

    function changeTreasuryFee(uint256 a, uint256 b) external onlyOwner {
        treasuryPercentOfSwapFee = WadRayMath.wadDiv(a, b);

        uint256 x = globalMintersPercentOfSwapFee + treasuryPercentOfSwapFee;

        require(x == MULTIPLIER, "ITF");

        emit ChangeTreasuryFee(a, b);
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

            zUSDMintAmount = zUSDMintAmount * 1 * HALF_MULTIPLIER;

            zUSDMintAmount = zUSDMintAmount / zTokenUSDRate;

             /**
             * Track the USD value of the swap amount
             */
            swapAmountInUSD = _amount * HALF_MULTIPLIER;
            swapAmountInUSD = _amount / _zTokenFromUSDRate;

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

            getSwapReward();

            treasuryFeePerTransaction =
                treasuryPercentOfSwapFee *
                swapFeePerTransactionInUsd;

            treasuryFeePerTransaction = treasuryFeePerTransaction / MULTIPLIER;

            /**
             * Send the treasury amount to a treasury wallet
             */
            _mint(zUSD, treasuryWallet, treasuryFeePerTransaction);
            /**
             * Send the global minters fee from User to the global minters fee wallet
             */
            _mint(zUSD, address(this), globalMintersFeePerTransaction);
        }

        return zUSDMintAmount;
    }

    /**
     * Set Oracle contract address
     */
   function setOracleAddress(address _address) public {
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
    function getzUSDAddress() external returns(address) {
        return zUSD = BakiOracleInterface(Oracle).getZToken("zusd");
    }

     /**
    * View minter's reward Helper
    */
    function getSwapReward() internal returns(uint256) {
        uint256 x = netMintUser[msg.sender] * globalMintersFee;

        uint256 mintRatio = WadRayMath.wadDiv(
            x,
            netMintGlobal
        );

        userAccruedFeeBalance[msg.sender] = mintRatio / MULTIPLIER;

        return userAccruedFeeBalance[msg.sender];
    }

    /**
     * Helper function for global debt 
     */
    function getDebtHelper(string memory _zToken) internal view returns(uint256) {
        address _zTokenAddress = BakiOracleInterface(Oracle).getZToken(_zToken);

        uint256 singleZToken = WadRayMath.wadDiv(IERC20(_zTokenAddress).totalSupply(), 
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

    function getUserDebt(address user) external view returns (uint256) {
        return _updateUserDebtOutstanding(netMintUser[user], netMintGlobal);
    }

    /**
     * Get User Outstanding Debt
     */
 function _updateUserDebtOutstanding(
        uint256 _netMintUserzUSDValue,
        uint256 _netMintGlobalzUSDValue
    ) public view returns (uint256) {
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
                "IC"
            );
        }

        return true;
    }

    uint256[50] private __gap;
}
