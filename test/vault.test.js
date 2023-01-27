const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { Contract } = require("ethers");

var collateral;
var zUSD;
var zNGN;
var zZAR;
var zXAF;
var Oracle;

async function deployToken(_name, _symbol) {
  const ZToken = await ethers.getContractFactory("ZToken");
  console.log(`deploying ${_name}`);

  const ztoken = await ZToken.deploy(_name, _symbol);

  await ztoken.deployed();

  console.log(`${_name} token is deployed at ${ztoken.address}`);
  return ztoken.address;
}

async function deployCollateral(_name, _symbol) {
  const Cusd = await ethers.getContractFactory("CUSD");
  console.log(`deploying ${_name}`);

  const cusd = await Cusd.deploy(_name, _symbol);

  await cusd.deployed();

  console.log(`${_name} collateral is deployed at ${cusd.address}`);
  return cusd.address;
}

async function deployOracle() {
  const Oracle = await ethers.getContractFactory("BakiOracle");
  console.log("deploying oracle");

  const oracle = await Oracle.deploy();

  await oracle.deployed();

  console.log(`oracle is deployed is ${oracle.address}`);
  return oracle.address;
}

//collateral, zTokens and Oracle deploy function
async function deploy() {
   collateral = await deployCollateral("cUSD", "cUSD");

   zUSD = await deployToken("zUSD", "zUSD");
   zNGN = await deployToken("zNGN", "zNGN");
   zZAR = await deployToken("zZAR", "zZAR");
   zXAF = await deployToken("zXAF", "zXAF");

   Oracle = await deployOracle();

  console.log("Deploying Tokens and Oracles...");
}

describe("Vault", () => {
  let vault;

  beforeEach(async() => {
    //Deploy the contracts
    await deploy();
    
    const Vault = await ethers.getContractFactory("Vault");
       vault = await upgrades.deployProxy(
       Vault,
       [zUSD, zNGN, zXAF, zZAR, Oracle, collateral],
       {
         initializer: "vault_init",
       }
     );
    await vault.deployed();

    console.log(vault.address)
  });

  // it("it should deposit, collateral", async() => {
  //    const [sender] = await ethers.getSigners();

    
  //   const depositAmount = "0";
  //   const depositWeiAmount = ethers.utils.parseEther(depositAmount);
  //   const deposit = {
  //     value: depositWeiAmount,
  //   };

  //   const mintAmount = "50";
  //   // const mintWeiAmount = ethers.utils.parseEther(mintAmount);
  //   // const mint = {
  //   //   value: mintWeiAmount,
  //   // }

  //   //set allowance before deposit
  //   // await collateral.approve(vault, depositAmount)
  //   await collateral.name();

  //   // await vault.depositAndMint(depositAmount, mintAmount);
  //   await vault.viewMintersAddress();

  //   var balance = await vault.getUserCollateralBalance();

  //   expect(balance).to.equal(depositWeiAmount);
  // })
})