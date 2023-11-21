const { ethers, upgrades } = require("hardhat");


async function main() {
    const Token = await ethers.getContractFactory("Token");
    const token = await Token.deploy("DAI", "DAI");
    await token.deployed();
    console.log(` token is deployed at ${token.address}`);
  
    return token.address;


}

main();

// DAI 0x791e2a9F7671A90A04465691eAE56CC9CF2FD92E