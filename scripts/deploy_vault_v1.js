const { ethers, upgrades } = require("hardhat");

async function deployToken(_name, _symbol){
    const ZToken = await ethers.getContractFactory("ZToken");
    console.log(`deploying ${_name}`);

    const ztoken = await ZToken.deploy(_name, _symbol);

    await ztoken.deployed();

    console.log(`${_name} token is deployed at ${ztoken.address}`);
    return ztoken.address;
}

async function deployOracle(){
    const Oracle = await ethers.getContractFactory("BakiOracle");
    console.log("deploying oracle");

    const oracle = await Oracle.deploy();

    await oracle.deployed();
    
    console.log(`oracle is deployed is ${oracle.address}`);
    return oracle.address;

}

async function main() {
  const Vault = await ethers.getContractFactory("Vault");

  // deploy ztokens and oracle contracts 
const zUSD = await deployToken("zUSD", "zUSD");
const zNGN = await deployToken("zNGN", "zNGN");
const zZAR = await deployToken("zZAR", "zZAR");
const zXAF = await deployToken("zXAF", "zXAF");

const Oracle = await deployOracle();

console.log("Deploying Vault...");

  const vault = await upgrades.deployProxy(Vault, [zUSD, zNGN, zXAF, zZAR, Oracle], {
    initializer: "vault_init",
  });

  await vault.deployed();
  console.log("Vault deployed to:", vault.address);
}

main();
