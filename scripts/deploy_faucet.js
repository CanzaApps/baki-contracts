const { ethers, upgrades } = require("hardhat");


async function main() {
  const Faucet = await ethers.getContractFactory("Faucet");

  const faucet = await upgrades.deployProxy(
    Faucet, 
    [], 
    {
      initializer: "init",
    }
  );

  await faucet.deployed();
  console.log("Faucet deployed to:", faucet.address);


}

main();