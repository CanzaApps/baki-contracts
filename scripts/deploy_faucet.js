const { ethers, upgrades } = require("hardhat");


async function main() {
  const Faucet = await ethers.getContractFactory("Faucet");

  const faucet = await Faucet.deploy();

  await faucet.deployed();

  console.log("Faucet deployed to:", faucet.address);


}

main();