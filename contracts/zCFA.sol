
pragma solidity ^0.8.13;

//All our import Statements needed
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

 
//Create the Contract
contract ZCFA is ERC20 {

    constructor() ERC20("zCFA", "zCFA"){
      _mint(msg.sender, 1000000 ether);
    }

    // Mint this much tokens to the caller
    // OnlyVault modifier
    function mint(uint256 _amount) external  
    {
        _mint(msg.sender, _amount);
    }
}