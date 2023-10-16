// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/ZTokenInterface.sol";

contract Faucet is OwnableUpgradeable {
    mapping(string => address) public assets;
    address public avax;

    event AvaxFinished(address _avax, address faucet, uint256 balance);

     function init() external initializer {
        __Ownable_init();
    }


    function setAsset(string memory asset, address _address) external onlyOwner {
        require(_address != address(0), "address cannot be a zero address");
        assets[asset] = _address;
    }

     function setAvax(address _address) external onlyOwner {
        require(_address != address(0), "address cannot be a zero address");
        avax = _address;
    }

    function getAsset(string memory asset, address receiver) external {
        if(IERC20Upgradeable(avax).balanceOf(address(this)) > 0.02 ether){
            if(IERC20Upgradeable(avax).balanceOf(msg.sender) < 0.02 ether){
                IERC20Upgradeable(avax).approve(address(this), 0.02 ether);
                bool _success = IERC20Upgradeable(avax).transferFrom(address(this), msg.sender, 0.02 ether);
                if(!_success) revert();

            }
        } else {
            emit AvaxFinished(avax, address(this), IERC20Upgradeable(avax).balanceOf(msg.sender));
        }
        bool success = ZTokenInterface(assets[asset]).mint(receiver, 1000000 ether);
        if(!success) revert();
    }

  
}
