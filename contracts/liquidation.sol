// SPDX-License-Identifier: MIT

/**
 * NOTE
 * Always do additions first
 * Check if the substracting value is greater than or less than the added values i.e check for a negative result
 */

pragma solidity ^0.8.17;

import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/WadRayMath.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IALALiquidation.sol";
import "./Vault.sol";


contract Liquidation is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{

     uint256 private constant USD = 1e3;

    uint256 private constant MULTIPLIER = 1e6;

    uint256 private constant HALF_MULTIPLIER = 1e3;

    uint256 public COLLATERIZATION_RATIO_THRESHOLD;


    using AddressUpgradeable for address;

    Vault public vault;
    IALALiquidation public alaLiquidation;

    address private vaultAddress;

    enum Status {
        Pending,
        Active,
        Closed
    }

    struct LiquidationState {
        Status status;
        uint256 totalLiquidationAmount;
        address [] userBellowCollateralRatio; 
    }

   
   LiquidationState [] public liquidationState;

   address [] private userBellowCollateralRatio;

   uint256 private totalUserDebt = 0;
   uint256 private totalCollateralBalance = 0;

   struct MinterData{
     address userAddress;
     uint256 collateralLiquidated;
     uint256 debt;
   }

    event Liquidate(
        address indexed liquidator,
        uint256 indexed totalDebt,
        uint256 totalCollateral
    );




    constructor(address _vaultAddress, address _alaAddress) {
      require(_vaultAddress != address(0), "Vault Address must be non-zero");
      require(_alaAddress != address(0), "ALA Address must be non-zero");
      vaultAddress = _vaultAddress;
      vault = Vault(_vaultAddress);
      alaLiquidation = IALALiquidation(_alaAddress);
    }

    /**
     * set collaterization ratio threshold
     */
    function setCollaterizationRatioThreshold(
        uint256 _value
    ) external onlyOwner {
        // Set an upper and lower bound on the new value of collaterization ratio threshold
        require(
            _value > 12 * 1e2 || _value < 20 * 1e2,
            "value must be within the set limit"
        );

        COLLATERIZATION_RATIO_THRESHOLD = _value;

        // emit SetCollaterizationRatioThreshold(_value);
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
     * Check User for liquidation
     */
    function checkUserForLiquidation(uint256 _usdValueOfCollateral, uint256 userDebt ) public view returns (bool) {

        if (userDebt != 0) {
            uint256 userCollateralRatio =
                1e3 *
                WadRayMath.wadDiv(_usdValueOfCollateral, userDebt);

            userCollateralRatio = userCollateralRatio / MULTIPLIER;

            if (userCollateralRatio < COLLATERIZATION_RATIO_THRESHOLD) {
                return true;
            }
        }

        return false;
    }


 function liquidate() external nonReentrant {

        uint256 userCount = 0;
        uint256 totalDebt = 0;
        uint256 collateralBalanceTotal = 0;
        address [] memory mintersAddresses = vault.getMinters();
        address[] memory belowRatioUsers = new address[](mintersAddresses.length);

        for (uint256 i = 0; i < mintersAddresses.length; i++) {
        uint256 userDebt = vault.getUserDebt(mintersAddresses[i]);  
        uint256 collateralBalanceInUSD = vault.getCollateralBalanceByUserInUSD(mintersAddresses[i]);
        uint256 collateralBalance = vault.getCollateralBalanceByUser(mintersAddresses[i]);
        bool isBelowLiquidation = checkUserForLiquidation(collateralBalanceInUSD, userDebt);

        if (isBelowLiquidation) {
            totalDebt += userDebt;
            collateralBalanceTotal += collateralBalance;
            belowRatioUsers[userCount++] = mintersAddresses[i];
        }

        }

        // Resize the belowRatioUsers array to the correct size
        address[] memory resizedBelowRatioUsers = new address[](userCount);
        for (uint256 i = 0; i < userCount; i++) {
            resizedBelowRatioUsers[i] = belowRatioUsers[i];
        }

        vault.updateUsersCollateralBalance(resizedBelowRatioUsers, 0);
        vault.updateNetMintUsers(resizedBelowRatioUsers, 0);

        vault.releaseCollateralAmount(collateralBalanceTotal);

        totalUserDebt += totalDebt;
        totalCollateralBalance += collateralBalanceTotal;


        emit Liquidate(msg.sender, totalDebt, collateralBalanceTotal);
    }
    


    function releaseReward(uint256 expectedReward) external {
        require(totalCollateralBalance >= expectedReward, "Insufficient collateral");
        address zUSD = vault.getZUSD();
        /**
         * check if the liquidator has sufficient zUSD to repay the debt
         * burn the zUSD
         */
        require(
            IERC20(zUSD).balanceOf(msg.sender) >= totalUserDebt,
            "Liquidator does not have sufficient zUSD to repay debt"
        );

        totalUserDebt = 0;

        _burn(zUSD, msg.sender, totalUserDebt);
 
         address collateral = vault.getCollateralTokenAddress();


        bool transferSuccess = IERC20(collateral).transfer(
            msg.sender,
            expectedReward
        );
       
    }


    function getAmountToLiquidate() external view returns (uint256) {
        return totalUserDebt;
    }
    
       


}
