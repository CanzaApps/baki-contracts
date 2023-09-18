const { ethers, upgrades } = require("hardhat");
const { getImplementationAddress } = require('@openzeppelin/upgrades-core');

let tokens = {
  zusd: null,
  zngn: null,
  zzar: null,
  zxaf: null,
};

async function deployToken(_name, _symbol) {
  const ZToken = await ethers.getContractFactory("ZToken");
  console.log(`deploying ${_name}`);

  const ztoken = await ZToken.deploy(_name, _symbol);

  await ztoken.deployed();
  tokens[_name] = ztoken.address;
  console.log(`${_name} token is deployed at ${ztoken.address}`);
  return ztoken.address;
}



async function deployOracle(_datafeed, _zusd, _zngn, _zzar ,_zxaf) {
  const Oracle = await ethers.getContractFactory("ChainlinkOracle");
  console.log("deploying oracle");

  const oracle = await Oracle.deploy(_datafeed, _zusd, _zngn, _zzar ,_zxaf);

  await oracle.deployed();

  console.log(`oracle is deployed is ${oracle.address}`);
  return oracle.address;
}


async function deployCollateral() {
  const Cusd = await ethers.getContractFactory("USDC");
  console.log(`deploying USDC`);

  const usdc = await Cusd.deploy();

  await usdc.deployed();

  console.log(`USDC collateral is deployed at ${usdc.address}`);
  return usdc.address;
}

async function setVaultAddress(_name, _vaultAddress, liqAddr) {
  const zToken = await hre.ethers.getContractAt("ZToken", tokens[_name]);

  const txn = await zToken.addVaultAddress(_vaultAddress);
  const txn1 = await zToken.addLiquidationAddress(liqAddr);

  console.log(`Set Vault address on ${_name}:`, txn.hash);
  //console.log(`Set Liq address on ${_name}:`, txn1.hash);
}

async function deployCollateral() {
  const Cusd = await ethers.getContractFactory("USDC");
  console.log(`deploying USDC`);

  const usdc = await Cusd.deploy();

  await usdc.deployed();

  console.log(`USDC collateral is deployed at ${usdc.address}`);
  return usdc.address;
}

async function deployLiquidation(_vaultAddress) {
    try{
    console.log("vault", _vaultAddress)
  const Liquidation = await ethers.getContractFactory("Liquidation");
  //console.log("liq", Liquidation)
  const liquidation = await upgrades.deployProxy(Liquidation, [_vaultAddress], {
    initializer: "init",
  })
  await liquidation.deployed();
  console.log("Liquidation deployed to: ", liquidation.address)
  return liquidation.address;
    }catch(err) {
        console.log(err)
    }
}

async function main() {
  //const Vault = await ethers.getContractFactory("Vault");
  // const proxyAddress = '0x48c35B4458237975aA572b4480cC93FE7535a2AC'; // replace with your proxy contract address

  // const provider = ethers.provider;
  // const implementationAddress = await getImplementationAddress(provider, proxyAddress);

  // console.log('Implementation contract address:', implementationAddress);

  //deploy ztokens and oracle contracts
  // const zUSD = await deployToken("zusd", "zusd");
  // const zNGN = await deployToken("zngn", "zngn");
  // const zZAR = await deployToken("zzar", "zzar");
  // const zXAF = await deployToken("zxaf", "zxaf");

  // const collateral = await deployCollateral();

  const Oracle = await deployOracle("0x4281ecf07378ee595c564a59048801330f3084ee", "0x4281ecf07378ee595c564a59048801330f3084ee", "0x4281ecf07378ee595c564a59048801330f3084ee", "0x4281ecf07378ee595c564a59048801330f3084ee", "0x4281ecf07378ee595c564a59048801330f3084ee");

  console.log(Oracle);

  // const vault = await upgrades.deployProxy(
  //   Vault,
  //   [Oracle, collateral],
  //   {
  //     initializer: "vault_init",
  //   }
  // );

  //await Oracle.deployed();
  //console.log("Vault deployed to:", vault.address);

  // const liqAddr = await deployLiquidation(vault.address);
  // console.log("here", liqAddr)

    // await setVaultAddress("zusd", vault.address, liqAddr);
    // await setVaultAddress("zngn", vault.address, liqAddr);
    // await setVaultAddress("zzar", vault.address, liqAddr);
    // await setVaultAddress("zxaf", vault.address, liqAddr);
}

main();
